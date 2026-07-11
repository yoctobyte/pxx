{ SPDX-License-Identifier: Zlib }
unit dns_async;
{ Async DNS resolution over the coroutine reactor (feature-own-net-http-lib /
  feature-dns-resolver-library). Same wire format as the blocking resolver
  (dns_wire_core builds/parses), but the UDP query yields the coroutine on the
  reactor instead of blocking the thread — so HttpGetAsync can take hostnames.
  Call from inside a coroutine; drive with RunUntilDone.

  resolv.conf / hosts are read synchronously (small local files, no async file
  I/O); only the network round-trip is async. Parity with the blocking facade:
  per-query timeout (reactor timerfd), multi-nameserver retry, glibc search/
  ndots candidates, CNAME chain chase. Still IPv4 A records only, and a
  truncated (TC) response does not yet retry over TCP (later slice — needs the
  async stream-connect path). }

interface

uses scheduler, platform, dns, dns_config, dns_wire_core, dns_wire_blocking;

{ Async A-record query to an explicit nameserver (host byte order) + port,
  bounded by timeoutMs (PAL_NET_ETIMEDOUT when it lapses; < 0 = unbounded).
  Returns the DNS RCODE (0 = NOERROR, ips[0..count-1] filled), or a negative
  DNS_ERR_* / transport error. When the answer is an alias with no A records
  (rcode 0, count 0), cname carries the target for chain chasing ('' else). }
function DnsQueryAAsyncEx(nsHost: LongWord; nsPort: Integer; const name: string;
  var ips: TDnsIpv4Array; var count: Integer; var cname: string; timeoutMs: Integer): Integer;

{ Back-compat wrapper: DnsQueryAAsyncEx with a 5s timeout, cname dropped. }
function DnsQueryAAsync(nsHost: LongWord; nsPort: Integer; const name: string;
  var ips: TDnsIpv4Array; var count: Integer): Integer;

{ DnsQueryAAsyncEx across a nameserver list: first definitive answer (any
  rcode) wins; transport failures fall through to the next nameserver. }
function DnsQueryAListAsyncEx(const ns: TDnsIpv4Array; nsCount, nsPort: Integer;
  const name: string; var ips: TDnsIpv4Array; var count: Integer; var cname: string;
  timeoutMs: Integer): Integer;

{ Async mirror of dns.DnsResolveChase: one exact query name through the
  nameserver list, CNAME chain chased across follow-up queries (bound
  DNS_MAX_CNAME_CHAIN). }
function DnsResolveChaseAsync(const ns: TDnsIpv4Array; nsCount, nsPort: Integer;
  const name: string; var ips: TDnsIpv4Array; var count: Integer; timeoutMs: Integer): Integer;

{ Full async resolve: dotted-quad shortcut, then /etc/hosts, then every
  configured nameserver with search/ndots candidates and CNAME chasing.
  Mirror of dns.DnsResolveHost but reactor-driven. }
function DnsResolveHostAsync(const name: string; var ips: TDnsIpv4Array; var count: Integer): Integer;

implementation

function DnsQueryAAsyncEx(nsHost: LongWord; nsPort: Integer; const name: string;
  var ips: TDnsIpv4Array; var count: Integer; var cname: string; timeoutMs: Integer): Integer;
var
  sock, qlen, rcode, outId, qid, rc, i: Integer;
  n: Int64;
  qbuf: array[0..511] of Byte;
  rbuf: array[0..1535] of Byte;
  fromAddr: LongWord;
  fromPort: Integer;
  localIps: TDnsIpv4Array;
  localCount: Integer;
  chase: string;
begin
  count := 0;
  cname := '';
  sock := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  if sock < 0 then begin Result := sock; Exit; end;
  rc := PalSetSocketNonBlocking(sock, 1);

  qid := NextQueryId;
  qlen := DnsBuildQueryA(name, qid, @qbuf[0], 512);
  if qlen <= 0 then begin rc := PalSocketClose(sock); Result := qlen; Exit; end;

  if PalSendToIpv4(sock, @qbuf[0], qlen, nsHost, nsPort) < 0 then
  begin rc := PalSocketClose(sock); Result := DNS_ERR_SHORT; Exit; end;

  { Park on the reactor until the datagram is readable or the timer lapses;
    tolerate a spurious wake. A timed-out park still tries one nonblocking
    recv (both-ready race, see WaitReadableTimeout). }
  n := PAL_NET_EAGAIN;
  while n = PAL_NET_EAGAIN do
  begin
    if WaitReadableTimeout(sock, timeoutMs) then
      n := PalRecvFromIpv4(sock, @rbuf[0], 1536, fromAddr, fromPort)
    else
    begin
      n := PalRecvFromIpv4(sock, @rbuf[0], 1536, fromAddr, fromPort);
      if n = PAL_NET_EAGAIN then
      begin
        rc := PalSocketClose(sock);
        Result := PAL_NET_ETIMEDOUT;
        Exit;
      end;
    end;
  end;
  rc := PalSocketClose(sock);
  if n <= 0 then begin Result := DNS_ERR_SHORT; Exit; end;

  { Parse into locals, then copy out — never forward a var param into another
    routine's var param (feature-riscv32-var-param-forwarding). }
  localCount := 0;
  outId := 0;
  rcode := DnsParseResponseA(@rbuf[0], Integer(n), localIps, localCount, outId);
  if rcode < 0 then begin Result := rcode; Exit; end;
  if outId <> qid then begin Result := DNS_ERR_BADID; Exit; end;
  for i := 0 to localCount - 1 do
    ips[i] := localIps[i];
  count := localCount;
  if (rcode = 0) and (localCount = 0) then
  begin
    chase := '';
    if DnsExtractCname(@rbuf[0], Integer(n), chase) then
      cname := chase;
  end;
  Result := rcode;
end;

function DnsQueryAAsync(nsHost: LongWord; nsPort: Integer; const name: string;
  var ips: TDnsIpv4Array; var count: Integer): Integer;
var
  localIps: TDnsIpv4Array;
  localCount, rc, i: Integer;
  cname: string;
begin
  count := 0;
  localCount := 0;
  cname := '';
  rc := DnsQueryAAsyncEx(nsHost, nsPort, name, localIps, localCount, cname, 5000);
  for i := 0 to localCount - 1 do
    ips[i] := localIps[i];
  count := localCount;
  Result := rc;
end;

function DnsQueryAListAsyncEx(const ns: TDnsIpv4Array; nsCount, nsPort: Integer;
  const name: string; var ips: TDnsIpv4Array; var count: Integer; var cname: string;
  timeoutMs: Integer): Integer;
var
  i, j, rc, localCount: Integer;
  localIps: TDnsIpv4Array;
  localCname: string;
begin
  count := 0;
  cname := '';
  if nsCount <= 0 then begin Result := DNS_ERR_NONS; Exit; end;
  rc := DNS_ERR_NONS;
  for i := 0 to nsCount - 1 do
  begin
    localCount := 0;
    localCname := '';
    rc := DnsQueryAAsyncEx(ns[i], nsPort, name, localIps, localCount, localCname, timeoutMs);
    if rc >= 0 then
    begin
      { definitive answer (even NXDOMAIN) — copy out and stop }
      for j := 0 to localCount - 1 do
        ips[j] := localIps[j];
      count := localCount;
      cname := localCname;
      Result := rc;
      Exit;
    end;
    { negative = transport failure (incl. timeout); next nameserver }
  end;
  Result := rc;
end;

function DnsResolveChaseAsync(const ns: TDnsIpv4Array; nsCount, nsPort: Integer;
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
    rc := DnsQueryAListAsyncEx(ns, nsCount, nsPort, cur, localIps, localCount, cname, timeoutMs);
    if rc < 0 then begin Result := rc; Exit; end;
    if (rc = 0) and (localCount = 0) and (Length(cname) > 0) then
      cur := cname   { alias with no address — follow the target }
    else
    begin
      for i := 0 to localCount - 1 do
        ips[i] := localIps[i];
      count := localCount;
      Result := rc;
      Exit;
    end;
  end;
  { chain exceeded the bound — last rcode, no addresses }
  Result := rc;
end;

function DnsResolveHostAsync(const name: string; var ips: TDnsIpv4Array; var count: Integer): Integer;
var
  hostsText, resolvText: string;
  ns, localIps: TDnsIpv4Array;
  search: TDnsSearchArray;
  nsCount, searchCount, ndots, localCount, rc, i, idx: Integer;
  hostIp, ip: LongWord;
  cand: string;
begin
  count := 0;

  { dotted-quad needs no network. }
  if DnsParseIpv4(name, 1, Length(name), ip) then
  begin ips[0] := ip; count := 1; Result := 0; Exit; end;

  { "files" first — an /etc/hosts entry wins. }
  rc := ReadFileText(PChar('/etc/hosts'), hostsText, 65536);
  hostIp := 0;
  if DnsLookupHosts(hostsText, name, hostIp) then
  begin ips[0] := hostIp; count := 1; Result := 0; Exit; end;

  { "dns" — every configured nameserver, glibc search-candidate order, CNAME
    chains chased; never public DNS. }
  rc := ReadFileText(PChar('/etc/resolv.conf'), resolvText, 8192);
  nsCount := 0;
  searchCount := 0;
  ndots := DNS_DEFAULT_NDOTS;
  rc := DnsParseResolvConfEx(resolvText, ns, nsCount, search, searchCount, ndots);
  if nsCount = 0 then begin Result := DNS_ERR_NOCONFIG; Exit; end;

  rc := DNS_ERR_NOCONFIG;
  idx := 0;
  cand := '';
  while DnsQueryCandidate(name, search, searchCount, ndots, idx, cand) do
  begin
    localCount := 0;
    rc := DnsResolveChaseAsync(ns, nsCount, DNS_PORT, cand, localIps, localCount, 2000);
    if rc < 0 then begin Result := rc; Exit; end;   { transport-dead resolvers — stop }
    if (rc = 0) and (localCount > 0) then
    begin
      for i := 0 to localCount - 1 do
        ips[i] := localIps[i];
      count := localCount;
      Result := 0;
      Exit;
    end;
    idx := idx + 1;   { NXDOMAIN / empty — next candidate }
  end;
  Result := rc;
end;

end.
