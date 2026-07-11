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

uses scheduler, platform, dns, dns_cache, dns_config, dns_wire_core, dns_wire_blocking;

{ Async A-record query to an explicit nameserver (host byte order) + port,
  bounded by timeoutMs (PAL_NET_ETIMEDOUT when it lapses; < 0 = unbounded).
  Returns the DNS RCODE (0 = NOERROR, ips[0..count-1] filled), or a negative
  DNS_ERR_* / transport error. When the answer is an alias with no A records
  (rcode 0, count 0), cname carries the target for chain chasing ('' else).
  ttl (seconds) is the cache lifetime the response allows: the minimum answer
  TTL for a positive answer, the RFC 2308 negative TTL for NXDOMAIN/NODATA, or
  0 when nothing is cacheable (error / no SOA). }
function DnsQueryAAsyncTTL(nsHost: LongWord; nsPort: Integer; const name: string;
  var ips: TDnsIpv4Array; var count: Integer; var cname: string; var ttl: Integer;
  timeoutMs: Integer): Integer;

{ DnsQueryAAsyncTTL without the ttl out-param (ttl dropped). }
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

{ Async AAAA (IPv6) query to an explicit nameserver, timeout-bounded like the A
  path. Addresses come back 16 bytes each (network byte order). CNAME chasing
  and TCP fallback are not applied here yet (mirrors the sync AAAA slice). }
function DnsQueryAAAAAsync(nsHost: LongWord; nsPort: Integer; const name: string;
  var ips: TDnsIpv6Array; var count: Integer; timeoutMs: Integer): Integer;

{ DnsQueryAAAAAsync across a nameserver list (first definitive answer wins). }
function DnsQueryAAAAListAsync(const ns: TDnsIpv4Array; nsCount, nsPort: Integer;
  const name: string; var ips: TDnsIpv6Array; var count: Integer; timeoutMs: Integer): Integer;

{ Async AAAA sibling of dns.DnsResolveHost6: resolv.conf nameservers + glibc
  search/ndots candidates. /etc/hosts IPv6 lines and AAAA CNAME chasing are not
  consulted yet (same limits as the sync facade). }
function DnsResolveHost6Async(const name: string; var ips: TDnsIpv6Array; var count: Integer): Integer;

{ Cached A query for an exact name against the nameserver list. Consults `c` at
  `nowMs` first — a live positive OR negative entry short-circuits the network —
  and on a miss queries, then stores the answer under its TTL (positive: min
  answer TTL; negative NXDOMAIN/NODATA carrying an SOA: RFC 2308 negative TTL).
  `rcode` is the DNS RCODE. CNAME-chase results are not cached (the exact name
  is; a following chase query is a separate lookup on its own key). }
function DnsQueryAListCachedAsync(var c: TDnsCache; const ns: TDnsIpv4Array;
  nsCount, nsPort: Integer; const name: string; nowMs: Int64;
  var ips: TDnsIpv4Array; var count: Integer; var rcode: Integer; timeoutMs: Integer): Integer;

implementation

function DnsQueryAAsyncTTL(nsHost: LongWord; nsPort: Integer; const name: string;
  var ips: TDnsIpv4Array; var count: Integer; var cname: string; var ttl: Integer;
  timeoutMs: Integer): Integer;
var
  sock, qlen, rcode, outId, qid, rc, i: Integer;
  n: Int64;
  qbuf: array[0..511] of Byte;
  rbuf: array[0..1535] of Byte;
  fromAddr: LongWord;
  fromPort: Integer;
  localIps: TDnsIpv4Array;
  localCount, t: Integer;
  chase: string;
begin
  count := 0;
  cname := '';
  ttl := 0;
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
  if localCount > 0 then
  begin
    { positive: cache for the shortest answer TTL }
    t := DnsAnswerMinTTL(@rbuf[0], Integer(n));
    if t > 0 then ttl := t;
  end
  else if rcode = 0 then
  begin
    { NODATA/alias: a CNAME with no address is chased (not cached here) }
    chase := '';
    if DnsExtractCname(@rbuf[0], Integer(n), chase) then
      cname := chase
    else
    begin
      t := DnsNegativeTTL(@rbuf[0], Integer(n));   { NODATA negative TTL }
      if t > 0 then ttl := t;
    end;
  end
  else
  begin
    { NXDOMAIN etc.: negative TTL from the SOA }
    t := DnsNegativeTTL(@rbuf[0], Integer(n));
    if t > 0 then ttl := t;
  end;
  Result := rcode;
end;

function DnsQueryAAsyncEx(nsHost: LongWord; nsPort: Integer; const name: string;
  var ips: TDnsIpv4Array; var count: Integer; var cname: string; timeoutMs: Integer): Integer;
var
  localIps: TDnsIpv4Array;
  localCount, ttl, rc, i: Integer;
  localCname: string;
begin
  count := 0;
  cname := '';
  localCount := 0;
  ttl := 0;
  localCname := '';
  rc := DnsQueryAAsyncTTL(nsHost, nsPort, name, localIps, localCount, localCname, ttl, timeoutMs);
  for i := 0 to localCount - 1 do
    ips[i] := localIps[i];
  count := localCount;
  cname := localCname;
  Result := rc;
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

function DnsQueryAAAAAsync(nsHost: LongWord; nsPort: Integer; const name: string;
  var ips: TDnsIpv6Array; var count: Integer; timeoutMs: Integer): Integer;
var
  sock, qlen, rcode, outId, qid, rc, i, j: Integer;
  n: Int64;
  qbuf: array[0..511] of Byte;
  rbuf: array[0..1535] of Byte;
  fromAddr: LongWord;
  fromPort: Integer;
  localIps: TDnsIpv6Array;
  localCount: Integer;
begin
  count := 0;
  sock := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  if sock < 0 then begin Result := sock; Exit; end;
  rc := PalSetSocketNonBlocking(sock, 1);

  qid := NextQueryId;
  qlen := DnsBuildQuery(name, DNS_TYPE_AAAA, qid, @qbuf[0], 512);
  if qlen <= 0 then begin rc := PalSocketClose(sock); Result := qlen; Exit; end;

  if PalSendToIpv4(sock, @qbuf[0], qlen, nsHost, nsPort) < 0 then
  begin rc := PalSocketClose(sock); Result := DNS_ERR_SHORT; Exit; end;

  { Same reactor + timeout dance as the A path (WaitReadableTimeout). }
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

  { Parse into locals, then copy out (no var->var forwarding). }
  localCount := 0;
  outId := 0;
  rcode := DnsParseResponseAAAA(@rbuf[0], Integer(n), localIps, localCount, outId);
  if rcode < 0 then begin Result := rcode; Exit; end;
  if outId <> qid then begin Result := DNS_ERR_BADID; Exit; end;
  for i := 0 to localCount - 1 do
    for j := 0 to 15 do
      ips[i][j] := localIps[i][j];
  count := localCount;
  Result := rcode;
end;

function DnsQueryAAAAListAsync(const ns: TDnsIpv4Array; nsCount, nsPort: Integer;
  const name: string; var ips: TDnsIpv6Array; var count: Integer; timeoutMs: Integer): Integer;
var
  i, j, k, rc, localCount: Integer;
  localIps: TDnsIpv6Array;
begin
  count := 0;
  if nsCount <= 0 then begin Result := DNS_ERR_NONS; Exit; end;
  rc := DNS_ERR_NONS;
  for i := 0 to nsCount - 1 do
  begin
    localCount := 0;
    rc := DnsQueryAAAAAsync(ns[i], nsPort, name, localIps, localCount, timeoutMs);
    if rc >= 0 then
    begin
      for j := 0 to localCount - 1 do
        for k := 0 to 15 do
          ips[j][k] := localIps[j][k];
      count := localCount;
      Result := rc;
      Exit;
    end;
  end;
  Result := rc;
end;

function DnsResolveHost6Async(const name: string; var ips: TDnsIpv6Array; var count: Integer): Integer;
var
  resolvText: string;
  ns: TDnsIpv4Array;
  localIps: TDnsIpv6Array;
  search: TDnsSearchArray;
  nsCount, searchCount, ndots, localCount, rc, i, j, idx: Integer;
  cand: string;
begin
  count := 0;
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
    rc := DnsQueryAAAAListAsync(ns, nsCount, DNS_PORT, cand, localIps, localCount, 2000);
    if rc < 0 then begin Result := rc; Exit; end;
    if (rc = 0) and (localCount > 0) then
    begin
      for i := 0 to localCount - 1 do
        for j := 0 to 15 do
          ips[i][j] := localIps[i][j];
      count := localCount;
      Result := 0;
      Exit;
    end;
    idx := idx + 1;
  end;
  Result := rc;
end;

function DnsQueryAListCachedAsync(var c: TDnsCache; const ns: TDnsIpv4Array;
  nsCount, nsPort: Integer; const name: string; nowMs: Int64;
  var ips: TDnsIpv4Array; var count: Integer; var rcode: Integer; timeoutMs: Integer): Integer;
var
  cIps, localIps: TDnsIpv4Array;
  cCount, cRcode, i, j, rc, localCount, ttl: Integer;
  cname: string;
begin
  count := 0;
  rcode := 0;
  { cache first — a live positive OR negative entry short-circuits the query }
  cCount := 0; cRcode := 0;
  if DnsCacheGet(c, name, DNS_TYPE_A, nowMs, cIps, cCount, cRcode) then
  begin
    for i := 0 to cCount - 1 do ips[i] := cIps[i];
    count := cCount;
    rcode := cRcode;
    Result := cRcode;
    Exit;
  end;

  { miss — query the nameserver list, keeping the ttl for the store }
  if nsCount <= 0 then begin Result := DNS_ERR_NONS; Exit; end;
  rc := DNS_ERR_NONS;
  for i := 0 to nsCount - 1 do
  begin
    localCount := 0; ttl := 0; cname := '';
    rc := DnsQueryAAsyncTTL(ns[i], nsPort, name, localIps, localCount, cname, ttl, timeoutMs);
    if rc >= 0 then
    begin
      for j := 0 to localCount - 1 do ips[j] := localIps[j];
      count := localCount;
      rcode := rc;
      { store positive/negative answers with a live TTL; ttl seconds -> ms }
      if ttl > 0 then
        DnsCachePut(c, name, DNS_TYPE_A, localIps, localCount, rc, nowMs, Int64(ttl) * 1000);
      Result := rc;
      Exit;
    end;
    { transport failure (incl. timeout) — try the next nameserver }
  end;
  Result := rc;
end;

end.
