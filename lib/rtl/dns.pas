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

function DnsResolveHost(const name: string; var ips: TDnsIpv4Array; var count: Integer): Integer;
var
  hostsText, resolvText: string;
  ns, localIps: TDnsIpv4Array;
  nsCount, localCount, rc, i: Integer;
  hostIp: LongWord;
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

  { "dns" — try every configured nameserver in order; never public DNS. }
  nsCount := 0;
  rc := DnsParseResolvConf(resolvText, ns, nsCount);
  if nsCount = 0 then
  begin
    DnsResolveHost := DNS_ERR_NOCONFIG;
    Exit;
  end;
  localCount := 0;
  rc := DnsResolveAList(ns, nsCount, DNS_PORT, name, localIps, localCount, 2000);
  if rc >= 0 then
  begin
    for i := 0 to localCount - 1 do
      ips[i] := localIps[i];
    count := localCount;
  end;
  DnsResolveHost := rc;
end;

end.
