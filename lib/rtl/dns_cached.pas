{ SPDX-License-Identifier: Zlib }
unit dns_cached;
{ Cache-backed async DNS resolution (feature-dns-resolver-library) — the layer
  that ties dns_async's reactor queries to the dns_cache TTL cache. Kept in its
  OWN unit, deliberately NOT pulled into dns_async, because a program that
  transitively `uses dns_cache` alongside the managed-string http stack
  miscompiles today (a Track A unit-graph/codegen bug —
  bug-transitive-dns_cache-import-corrupts-managed-strings). Apps that want
  caching import this unit explicitly; the base async resolver (and thus http)
  stays clear of dns_cache until that bug is fixed.

  Caches exact-name A answers only: a CNAME chase issues a fresh query for the
  target (that target is itself cacheable on its own key). Positive answers use
  the minimum answer TTL; negative answers (NXDOMAIN/NODATA carrying an SOA) use
  the RFC 2308 negative TTL. Time is the caller's `nowMs` (PalMonotonicMillis in
  production) so the policy stays explicit and testable. }

interface

uses platform, dns_cache, dns_wire_core, dns_wire_blocking, dns_async;

{ Cached A query for an exact name against the nameserver list. Consults `c` at
  `nowMs` first — a live positive OR negative entry short-circuits the network —
  and on a miss queries, then stores the answer under its TTL. Returns the DNS
  RCODE (also via rcode), or a negative transport error on total failure. }
function DnsQueryAListCachedAsync(var c: TDnsCache; const ns: TDnsIpv4Array;
  nsCount, nsPort: Integer; const name: string; nowMs: Int64;
  var ips: TDnsIpv4Array; var count: Integer; var rcode: Integer; timeoutMs: Integer): Integer;

implementation

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
