{ SPDX-License-Identifier: Zlib }
unit dns;
{ Resolver facade (feature-dns-resolver-library): host -> A records using the
  "files dns" order — consult /etc/hosts first, then query a configured
  nameserver over UDP via the dns_wire path. This is the stable entrypoint; the
  selectable dns_libc / dns_resolved / dns_esp backends and an async sibling come
  later. Public DNS is never assumed: with no configured nameserver and no hosts
  match, resolution fails (DNS_ERR_NOCONFIG) rather than reaching out to a public
  resolver. }

interface

uses platform, dns_wire_core, dns_config, dns_wire_blocking;

const
  DNS_ERR_NOCONFIG = -4;   { no /etc/resolv.conf nameserver and no hosts match }
  DNS_MAX_CNAME_CHAIN = 4; { alias-chase bound (resolver policy, matches BIND's 8/2 spirit) }

{ Testable seam: resolve `name` against the given hosts text first, then (on a
  miss) query nameserver nsHost:nsPort over UDP. Returns 0 (RCODE NOERROR) with
  ips/count filled, or a negative DNS_ERR_* / PAL error. }
function DnsResolveHostEx(const hostsText: string; nsHost: LongWord; nsPort: Integer;
  const name: string; var ips: TDnsIpv4Array; var count: Integer; timeoutMs: Integer): Integer;

{ Convenience entrypoint: read /etc/hosts and /etc/resolv.conf via PAL, then
  resolve using the first configured nameserver on the standard DNS port.
  Returns DNS_ERR_NOCONFIG if nothing in hosts matches and no nameserver is
  configured. }
function DnsResolveHost(const name: string; var ips: TDnsIpv4Array; var count: Integer): Integer;

{ Resolve A records for one exact query name through the nameserver list,
  chasing a CNAME chain across follow-up queries (bounded by
  DNS_MAX_CNAME_CHAIN). No hosts/search policy — the building block under
  DnsResolveHost, exported for tests and direct use. }
function DnsResolveChase(const ns: TDnsIpv4Array; nsCount, nsPort: Integer;
  const name: string; var ips: TDnsIpv4Array; var count: Integer; timeoutMs: Integer): Integer;

implementation

function DnsResolveHostEx(const hostsText: string; nsHost: LongWord; nsPort: Integer;
  const name: string; var ips: TDnsIpv4Array; var count: Integer; timeoutMs: Integer): Integer;
var
  hostIp: LongWord;
  localIps: TDnsIpv4Array;
  localCount, rc, i: Integer;
begin
  count := 0;
  { "files": an /etc/hosts match short-circuits the query. }
  hostIp := 0;
  if DnsLookupHosts(hostsText, name, hostIp) then
  begin
    ips[0] := hostIp;
    count := 1;
    DnsResolveHostEx := 0;
    Exit;
  end;
  { "dns": query the nameserver. Use locals + copy so a var parameter is never
    forwarded into another routine's var parameter
    (feature-riscv32-var-param-forwarding). }
  localCount := 0;
  rc := DnsResolveA(nsHost, nsPort, name, localIps, localCount, timeoutMs);
  if rc < 0 then
  begin
    DnsResolveHostEx := rc;
    Exit;
  end;
  for i := 0 to localCount - 1 do
    ips[i] := localIps[i];
  count := localCount;
  DnsResolveHostEx := rc;
end;

{ Read up to maxLen bytes of a file into s via PAL. Returns the byte count, or a
  negative PAL error / -1 if the file cannot be opened. }
function ReadFileText(path: PChar; var s: string; maxLen: Integer): Integer;
var
  fd, i: Integer;
  n: Int64;
  buf: array[0..4095] of Byte;
  total: Integer;
begin
  s := '';
  fd := PalOpen(path, PAL_OPEN_READ, 0);
  if fd < 0 then
  begin
    ReadFileText := -1;
    Exit;
  end;
  total := 0;
  repeat
    n := PalRead(fd, @buf[0], 4096);
    if n > 0 then
    begin
      for i := 0 to Integer(n) - 1 do
      begin
        if total < maxLen then
        begin
          s := s + Chr(buf[i]);
          total := total + 1;
        end;
      end;
    end;
  until (n <= 0) or (total >= maxLen);
  PalClose(fd);
  ReadFileText := total;
end;

function DnsResolveChase(const ns: TDnsIpv4Array; nsCount, nsPort: Integer;
  const name: string; var ips: TDnsIpv4Array; var count: Integer; timeoutMs: Integer): Integer;
var
  localIps: TDnsIpv4Array;
  localCount, rc, i, depth: Integer;
  cur, cname: string;
begin
  count := 0;
  cur := name;
  rc := DNS_ERR_NOCONFIG;
  for depth := 0 to DNS_MAX_CNAME_CHAIN - 1 do
  begin
    localCount := 0;
    cname := '';
    rc := DnsResolveAListEx(ns, nsCount, nsPort, cur, localIps, localCount, cname, timeoutMs);
    if rc < 0 then
    begin
      DnsResolveChase := rc;
      Exit;
    end;
    if (rc = 0) and (localCount = 0) and (Length(cname) > 0) then
    begin
      { alias with no address in the same response — follow the target }
      cur := cname;
      { loop on }
    end
    else
    begin
      for i := 0 to localCount - 1 do
        ips[i] := localIps[i];
      count := localCount;
      DnsResolveChase := rc;
      Exit;
    end;
  end;
  { chain exceeded the bound — return the last rcode with no addresses }
  DnsResolveChase := rc;
end;

function DnsResolveHost(const name: string; var ips: TDnsIpv4Array; var count: Integer): Integer;
var
  hostsText, resolvText: string;
  ns, localIps: TDnsIpv4Array;
  search: TDnsSearchArray;
  nsCount, searchCount, ndots, localCount, rc, i, idx: Integer;
  hostIp: LongWord;
  cand: string;
begin
  count := 0;
  rc := ReadFileText(PChar('/etc/hosts'), hostsText, 65536);
  rc := ReadFileText(PChar('/etc/resolv.conf'), resolvText, 8192);

  { "files" first — an /etc/hosts entry wins over any nameserver. }
  hostIp := 0;
  if DnsLookupHosts(hostsText, name, hostIp) then
  begin
    ips[0] := hostIp;
    count := 1;
    DnsResolveHost := 0;
    Exit;
  end;

  { "dns" — every configured nameserver, glibc search-list candidate order,
    CNAME chains chased; never public DNS. }
  nsCount := 0;
  searchCount := 0;
  ndots := DNS_DEFAULT_NDOTS;
  rc := DnsParseResolvConfEx(resolvText, ns, nsCount, search, searchCount, ndots);
  if nsCount = 0 then
  begin
    DnsResolveHost := DNS_ERR_NOCONFIG;
    Exit;
  end;
  rc := DNS_ERR_NOCONFIG;
  idx := 0;
  cand := '';
  while DnsQueryCandidate(name, search, searchCount, ndots, idx, cand) do
  begin
    localCount := 0;
    rc := DnsResolveChase(ns, nsCount, DNS_PORT, cand, localIps, localCount, 2000);
    if rc < 0 then
    begin
      { transport failure — the nameservers are unreachable; stop, do not walk
        the whole search list against a dead resolver }
      DnsResolveHost := rc;
      Exit;
    end;
    if (rc = 0) and (localCount > 0) then
    begin
      for i := 0 to localCount - 1 do
        ips[i] := localIps[i];
      count := localCount;
      DnsResolveHost := 0;
      Exit;
    end;
    { NXDOMAIN / no records — try the next candidate }
    idx := idx + 1;
  end;
  DnsResolveHost := rc;   { last rcode (e.g. NXDOMAIN), or NOCONFIG if no candidates }
end;

end.
