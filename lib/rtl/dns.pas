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

uses platform, dns_wire_core, dns_config, dns_wire_blocking, dns_cache;

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

{ AAAA sibling of DnsResolveChase: one exact query name through the nameserver
  list, CNAME chain chased across follow-up AAAA queries (bounded by
  DNS_MAX_CNAME_CHAIN), each hop consulting the process-wide cache. }
function DnsResolveChase6(const ns: TDnsIpv4Array; nsCount, nsPort: Integer;
  const name: string; var ips: TDnsIpv6Array; var count: Integer; timeoutMs: Integer): Integer;

{ AAAA (IPv6) sibling of DnsResolveHost: same "files dns" policy and search
  candidates, addresses come back as 16-byte network-order TDnsIpv6. An IPv6
  literal short-circuits without network; /etc/hosts IPv6 lines are consulted
  before the nameservers; CNAME chains are chased like the A path. }
function DnsResolveHost6(const name: string; var ips: TDnsIpv6Array; var count: Integer): Integer;

{ Process-wide facade answer cache (dns_cache, keyed on monotonic time):
  consulted by DnsResolveChase (and the async chase in dns_async) for exact
  query names. Positive answers live for their minimum answer TTL,
  NXDOMAIN/NODATA for the RFC 2308 negative TTL; alias (CNAME) hops are not
  cached yet. On by default; the cache is per-process and not thread-safe —
  multithreaded resolvers should disable it or serialize resolution. }
procedure DnsCacheSetEnabled(enabled: Boolean);
procedure DnsCacheFlush;

{ Shared-cache accessors (exported for the async facade and tests): look up /
  store an exact (name, qtype) answer against the process-wide cache at
  PalMonotonicMillis. Get returns True on a live hit — including a cached
  negative answer (count 0, the cached rcode). Put ignores ttlSec <= 0. Both
  are no-ops (miss) while the cache is disabled. }
function DnsGlobalCacheGet(const name: string; qtype: Integer;
  var ips: TDnsIpv4Array; var count: Integer; var rcode: Integer): Boolean;
procedure DnsGlobalCachePut(const name: string; qtype: Integer;
  const ips: TDnsIpv4Array; count, rcode, ttlSec: Integer);

{ AAAA siblings of the shared-cache accessors (qtype DNS_TYPE_AAAA implied). }
function DnsGlobalCacheGet6(const name: string;
  var ips: TDnsIpv6Array; var count: Integer; var rcode: Integer): Boolean;
procedure DnsGlobalCachePut6(const name: string;
  const ips: TDnsIpv6Array; count, rcode, ttlSec: Integer);

{ CNAME siblings: cache/look up the alias mapping name -> target (one entry
  serves A and AAAA chases — a CNAME applies to every query type). }
function DnsGlobalCacheGetCname(const name: string; var target: string): Boolean;
procedure DnsGlobalCachePutCname(const name, target: string; ttlSec: Integer);

implementation

var
  gCache: TDnsCache;
  gCacheReady: Boolean;   { lazy one-time init }
  gCacheOff: Boolean;     { zero-init = enabled }

procedure EnsureCache;
begin
  if not gCacheReady then
  begin
    DnsCacheInit(gCache);
    gCacheReady := True;
  end;
end;

procedure DnsCacheSetEnabled(enabled: Boolean);
begin
  gCacheOff := not enabled;
end;

procedure DnsCacheFlush;
begin
  DnsCacheInit(gCache);
  gCacheReady := True;
end;

function DnsGlobalCacheGet(const name: string; qtype: Integer;
  var ips: TDnsIpv4Array; var count: Integer; var rcode: Integer): Boolean;
var
  localIps: TDnsIpv4Array;
  localCount, localRcode, i: Integer;
begin
  count := 0;
  rcode := 0;
  DnsGlobalCacheGet := False;
  if gCacheOff then Exit;
  EnsureCache;
  { locals + copy: never forward a var parameter into another routine's var
    parameter (feature-riscv32-var-param-forwarding) }
  localCount := 0;
  localRcode := 0;
  if DnsCacheGet(gCache, name, qtype, PalMonotonicMillis, localIps, localCount, localRcode) then
  begin
    for i := 0 to localCount - 1 do
      ips[i] := localIps[i];
    count := localCount;
    rcode := localRcode;
    DnsGlobalCacheGet := True;
  end;
end;

procedure DnsGlobalCachePut(const name: string; qtype: Integer;
  const ips: TDnsIpv4Array; count, rcode, ttlSec: Integer);
begin
  if gCacheOff then Exit;
  if ttlSec <= 0 then Exit;
  EnsureCache;
  DnsCachePut(gCache, name, qtype, ips, count, rcode, PalMonotonicMillis, Int64(ttlSec) * 1000);
end;

function DnsGlobalCacheGet6(const name: string;
  var ips: TDnsIpv6Array; var count: Integer; var rcode: Integer): Boolean;
var
  localIps: TDnsIpv6Array;
  localCount, localRcode, i, k: Integer;
begin
  count := 0;
  rcode := 0;
  DnsGlobalCacheGet6 := False;
  if gCacheOff then Exit;
  EnsureCache;
  localCount := 0;
  localRcode := 0;
  if DnsCacheGet6(gCache, name, PalMonotonicMillis, localIps, localCount, localRcode) then
  begin
    for i := 0 to localCount - 1 do
      for k := 0 to 15 do
        ips[i][k] := localIps[i][k];
    count := localCount;
    rcode := localRcode;
    DnsGlobalCacheGet6 := True;
  end;
end;

procedure DnsGlobalCachePut6(const name: string;
  const ips: TDnsIpv6Array; count, rcode, ttlSec: Integer);
begin
  if gCacheOff then Exit;
  if ttlSec <= 0 then Exit;
  EnsureCache;
  DnsCachePut6(gCache, name, ips, count, rcode, PalMonotonicMillis, Int64(ttlSec) * 1000);
end;

function DnsGlobalCacheGetCname(const name: string; var target: string): Boolean;
var
  localTarget: string;
begin
  target := '';
  DnsGlobalCacheGetCname := False;
  if gCacheOff then Exit;
  EnsureCache;
  localTarget := '';
  if DnsCacheGetCname(gCache, name, PalMonotonicMillis, localTarget) then
  begin
    target := localTarget;
    DnsGlobalCacheGetCname := True;
  end;
end;

procedure DnsGlobalCachePutCname(const name, target: string; ttlSec: Integer);
begin
  if gCacheOff then Exit;
  if ttlSec <= 0 then Exit;
  EnsureCache;
  DnsCachePutCname(gCache, name, target, PalMonotonicMillis, Int64(ttlSec) * 1000);
end;

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
  localCount, rc, i, depth, crc, ttl: Integer;
  cur, cname: string;
begin
  count := 0;
  cur := name;
  rc := DNS_ERR_NOCONFIG;
  for depth := 0 to DNS_MAX_CNAME_CHAIN - 1 do
  begin
    localCount := 0;
    cname := '';
    crc := 0;
    if DnsGlobalCacheGet(cur, DNS_TYPE_A, localIps, localCount, crc) then
      rc := crc   { live cached answer (positive or negative) — no query }
    else if DnsGlobalCacheGetCname(cur, cname) then
      rc := 0     { cached alias hop — follow without a query }
    else
    begin
      ttl := 0;
      rc := DnsResolveAListTTL(ns, nsCount, nsPort, cur, localIps, localCount, cname, ttl, timeoutMs);
      if rc < 0 then
      begin
        DnsResolveChase := rc;
        Exit;
      end;
      if (rc = 0) and (localCount = 0) and (Length(cname) > 0) then
        DnsGlobalCachePutCname(cur, cname, ttl)   { alias: ttl = CNAME RR TTL }
      else
        DnsGlobalCachePut(cur, DNS_TYPE_A, localIps, localCount, rc, ttl);
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

function DnsResolveChase6(const ns: TDnsIpv4Array; nsCount, nsPort: Integer;
  const name: string; var ips: TDnsIpv6Array; var count: Integer; timeoutMs: Integer): Integer;
var
  localIps: TDnsIpv6Array;
  localCount, rc, i, j, depth, ttl, crc: Integer;
  cur, cname: string;
begin
  count := 0;
  cur := name;
  rc := DNS_ERR_NOCONFIG;
  for depth := 0 to DNS_MAX_CNAME_CHAIN - 1 do
  begin
    localCount := 0;
    cname := '';
    crc := 0;
    if DnsGlobalCacheGet6(cur, localIps, localCount, crc) then
      rc := crc   { live cached answer (positive or negative) — no query }
    else if DnsGlobalCacheGetCname(cur, cname) then
      rc := 0     { cached alias hop — follow without a query }
    else
    begin
      ttl := 0;
      rc := DnsResolveAAAAListTTL(ns, nsCount, nsPort, cur, localIps, localCount, cname, ttl, timeoutMs);
      if rc < 0 then
      begin
        DnsResolveChase6 := rc;
        Exit;
      end;
      if (rc = 0) and (localCount = 0) and (Length(cname) > 0) then
        DnsGlobalCachePutCname(cur, cname, ttl)   { alias: ttl = CNAME RR TTL }
      else
        DnsGlobalCachePut6(cur, localIps, localCount, rc, ttl);
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
        for j := 0 to 15 do
          ips[i][j] := localIps[i][j];
      count := localCount;
      DnsResolveChase6 := rc;
      Exit;
    end;
  end;
  { chain exceeded the bound — return the last rcode with no addresses }
  DnsResolveChase6 := rc;
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

function DnsResolveHost6(const name: string; var ips: TDnsIpv6Array; var count: Integer): Integer;
var
  resolvText, hostsText: string;
  ns: TDnsIpv4Array;
  localIps: TDnsIpv6Array;
  search: TDnsSearchArray;
  nsCount, searchCount, ndots, localCount, rc, i, j, idx: Integer;
  cand: string;
  lit6: TDnsIpv6;
begin
  count := 0;

  { an IPv6 literal needs no network }
  if DnsParseIpv6(name, 1, Length(name), lit6) then
  begin
    for j := 0 to 15 do ips[0][j] := lit6[j];
    count := 1;
    DnsResolveHost6 := 0;
    Exit;
  end;

  { "files" first — an /etc/hosts IPv6 entry wins over any nameserver. }
  rc := ReadFileText(PChar('/etc/hosts'), hostsText, 65536);
  if DnsLookupHosts6(hostsText, name, lit6) then
  begin
    for j := 0 to 15 do ips[0][j] := lit6[j];
    count := 1;
    DnsResolveHost6 := 0;
    Exit;
  end;

  rc := ReadFileText(PChar('/etc/resolv.conf'), resolvText, 8192);

  nsCount := 0;
  searchCount := 0;
  ndots := DNS_DEFAULT_NDOTS;
  rc := DnsParseResolvConfEx(resolvText, ns, nsCount, search, searchCount, ndots);
  if nsCount = 0 then
  begin
    DnsResolveHost6 := DNS_ERR_NOCONFIG;
    Exit;
  end;
  rc := DNS_ERR_NOCONFIG;
  idx := 0;
  cand := '';
  while DnsQueryCandidate(name, search, searchCount, ndots, idx, cand) do
  begin
    localCount := 0;
    rc := DnsResolveChase6(ns, nsCount, DNS_PORT, cand, localIps, localCount, 2000);
    if rc < 0 then
    begin
      DnsResolveHost6 := rc;
      Exit;
    end;
    if (rc = 0) and (localCount > 0) then
    begin
      for i := 0 to localCount - 1 do
        for j := 0 to 15 do
          ips[i][j] := localIps[i][j];
      count := localCount;
      DnsResolveHost6 := 0;
      Exit;
    end;
    idx := idx + 1;
  end;
  DnsResolveHost6 := rc;
end;

end.
