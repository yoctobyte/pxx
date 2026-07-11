program lib_dns_cache;
{ Offline test for dns_cache: TTL expiry, positive + negative entries, qtype
  separation, replace-in-place, and full-cache eviction of the soonest-expiring
  slot. Time is injected (nowMs) so no clock/network is involved. }

uses dns_wire_core, dns_cache;

var
  c: TDnsCache;
  ips: TDnsIpv4Array;
  cnt, rc, i: Integer;

procedure Show(const tag: string; pass: Boolean);
begin
  if pass then writeln(tag, '=ok') else writeln(tag, '=bad');
end;

procedure Zero(var a: TDnsIpv4Array);
var j: Integer;
begin
  for j := 0 to DNS_MAX_IPS - 1 do a[j] := 0;
end;

begin
  DnsCacheInit(c);

  { ---- positive entry, hit before expiry, miss after ---- }
  Zero(ips);
  ips[0] := LongWord($5DB8D822);   { 93.184.216.34 }
  DnsCachePut(c, 'example.com', DNS_TYPE_A, ips, 1, 0, 1000, 500);  { expires at 1500 }
  Zero(ips); cnt := -1; rc := -1;
  Show('hit',        DnsCacheGet(c, 'example.com', DNS_TYPE_A, 1200, ips, cnt, rc)
                     and (cnt = 1) and (ips[0] = LongWord($5DB8D822)) and (rc = 0));
  Show('miss-other', not DnsCacheGet(c, 'other.com', DNS_TYPE_A, 1200, ips, cnt, rc));
  Show('expired',    not DnsCacheGet(c, 'example.com', DNS_TYPE_A, 1600, ips, cnt, rc));

  { ---- negative entry (NXDOMAIN): a live hit that carries rcode 3, no addrs ---- }
  DnsCacheInit(c);
  Zero(ips);
  DnsCachePut(c, 'nope.test', DNS_TYPE_A, ips, 0, 3, 2000, 1000);  { NXDOMAIN, exp 3000 }
  cnt := -1; rc := -1;
  Show('neg-hit',    DnsCacheGet(c, 'nope.test', DNS_TYPE_A, 2500, ips, cnt, rc)
                     and (cnt = 0) and (rc = 3));
  Show('neg-expired', not DnsCacheGet(c, 'nope.test', DNS_TYPE_A, 3000, ips, cnt, rc));

  { ---- qtype separation: A and AAAA for one name are distinct slots ---- }
  DnsCacheInit(c);
  Zero(ips); ips[0] := 1;
  DnsCachePut(c, 'dual.test', DNS_TYPE_A,    ips, 1, 0, 0, 1000);
  Zero(ips); ips[0] := 2;
  DnsCachePut(c, 'dual.test', DNS_TYPE_AAAA, ips, 1, 0, 0, 1000);
  cnt := 0; rc := 0;
  Show('qtype-a',    DnsCacheGet(c, 'dual.test', DNS_TYPE_A,    100, ips, cnt, rc) and (ips[0] = 1));
  Show('qtype-aaaa', DnsCacheGet(c, 'dual.test', DNS_TYPE_AAAA, 100, ips, cnt, rc) and (ips[0] = 2));

  { ---- replace in place: same key updates, does not add a second slot ---- }
  DnsCacheInit(c);
  Zero(ips); ips[0] := 10;
  DnsCachePut(c, 'r.test', DNS_TYPE_A, ips, 1, 0, 0, 1000);
  Zero(ips); ips[0] := 20;
  DnsCachePut(c, 'r.test', DNS_TYPE_A, ips, 1, 0, 0, 1000);
  Show('replace-val',   DnsCacheGet(c, 'r.test', DNS_TYPE_A, 100, ips, cnt, rc) and (ips[0] = 20));
  Show('replace-count', DnsCacheLiveCount(c, 100) = 1);

  { ---- ttl<=0 is a no-op ---- }
  DnsCacheInit(c);
  Zero(ips); ips[0] := 7;
  DnsCachePut(c, 'z.test', DNS_TYPE_A, ips, 1, 0, 100, 0);
  Show('ttl-zero-noop', not DnsCacheGet(c, 'z.test', DNS_TYPE_A, 100, ips, cnt, rc));

  { ---- full-cache eviction: fill all slots, all live; one more evicts the
         soonest-expiring, live count stays at capacity ---- }
  DnsCacheInit(c);
  for i := 0 to DNS_CACHE_SLOTS - 1 do
  begin
    Zero(ips); ips[0] := LongWord(i + 1);
    { slot 0 expires soonest (expiry 50); the rest at 1000 }
    if i = 0 then
      DnsCachePut(c, 'k0', DNS_TYPE_A, ips, 1, 0, 0, 50)
    else
      DnsCachePut(c, 'k' + Chr(Ord('A') + i), DNS_TYPE_A, ips, 1, 0, 0, 1000);
  end;
  Show('full-live', DnsCacheLiveCount(c, 10) = DNS_CACHE_SLOTS);
  Zero(ips); ips[0] := $FF;
  DnsCachePut(c, 'knew', DNS_TYPE_A, ips, 1, 0, 10, 1000);   { forces eviction }
  Show('evict-cap',   DnsCacheLiveCount(c, 20) = DNS_CACHE_SLOTS);
  Show('evict-oldest', not DnsCacheGet(c, 'k0', DNS_TYPE_A, 20, ips, cnt, rc));
  Show('evict-newkept', DnsCacheGet(c, 'knew', DNS_TYPE_A, 20, ips, cnt, rc) and (ips[0] = $FF));
end.
