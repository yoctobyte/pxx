{ SPDX-License-Identifier: Zlib }
unit dns_cache;
{ TTL-aware DNS answer cache (feature-dns-resolver-library). A small fixed-size
  cache of A-record answers keyed by (name, qtype), each with an absolute expiry
  in monotonic milliseconds. Both positive answers (addresses) and negative
  answers (NXDOMAIN / NODATA — rcode with zero addresses) are cached, per RFC
  2308: a resolver must not re-query a name whose negative answer is still
  fresh. The negative TTL in real use is the SOA MINIMUM from the authority
  section; here the caller supplies the TTL so the logic stays pure and offline-
  testable (the resolver passes PalMonotonicMillis + the parsed TTL).

  Pure string/record -> data: no PAL, no network, no global state (the cache is
  a record the caller owns), so it is tested entirely offline like dns_config.
  Entries are keyed by (name, qtype): A entries carry IPv4 values, AAAA entries
  (the Put6/Get6 pair) carry 16-byte IPv6 values; one name can hold both. }

interface

uses dns_wire_core;   { TDnsIpv4Array, DNS_MAX_IPS }

const
  DNS_CACHE_SLOTS = 64;   { fixed capacity; evict the soonest-expiring on full }

type
  TDnsCacheEntry = record
    used:    Boolean;
    name:    string;
    qtype:   Integer;
    ips:     TDnsIpv4Array;
    ips6:    TDnsIpv6Array;   { AAAA values (qtype DNS_TYPE_AAAA entries) }
    count:   Integer;      { 0 = negative answer }
    rcode:   Integer;      { the cached DNS RCODE (0 NODATA / 3 NXDOMAIN / ...) }
    expiry:  Int64;        { absolute monotonic ms; entry dead once now >= this }
  end;

  TDnsCache = record
    slots: array[0..DNS_CACHE_SLOTS - 1] of TDnsCacheEntry;
  end;

{ Reset a cache to empty. Call once before first use. }
procedure DnsCacheInit(var c: TDnsCache);

{ Insert/replace the answer for (name, qtype). ttlMs <= 0 is a no-op (never
  cache an already-dead answer). count 0 caches a negative answer for ttlMs.
  On a full cache the soonest-expiring slot is reused. }
procedure DnsCachePut(var c: TDnsCache; const name: string; qtype: Integer;
  const ips: TDnsIpv4Array; count, rcode: Integer; nowMs, ttlMs: Int64);

{ Look up (name, qtype). Returns True with ips/count/rcode filled when a live
  (now < expiry) entry exists — including a negative one (True, count 0, the
  cached rcode). Returns False on a miss or an expired entry (and, as a side
  effect, reaps that expired slot). }
function DnsCacheGet(var c: TDnsCache; const name: string; qtype: Integer;
  nowMs: Int64; var ips: TDnsIpv4Array; var count: Integer; var rcode: Integer): Boolean;

{ AAAA siblings: insert / look up 16-byte IPv6 answers under qtype
  DNS_TYPE_AAAA. Same TTL/negative/eviction semantics as the A pair; an A and
  an AAAA entry for one name never collide (distinct qtype keys). }
procedure DnsCachePut6(var c: TDnsCache; const name: string;
  const ips6: TDnsIpv6Array; count, rcode: Integer; nowMs, ttlMs: Int64);
function DnsCacheGet6(var c: TDnsCache; const name: string; nowMs: Int64;
  var ips6: TDnsIpv6Array; var count: Integer; var rcode: Integer): Boolean;

{ Number of live (unexpired) entries at nowMs — for tests / diagnostics. }
function DnsCacheLiveCount(var c: TDnsCache; nowMs: Int64): Integer;

implementation

procedure DnsCacheInit(var c: TDnsCache);
var i: Integer;
begin
  for i := 0 to DNS_CACHE_SLOTS - 1 do
  begin
    c.slots[i].used := False;
    c.slots[i].name := '';
    c.slots[i].qtype := 0;
    c.slots[i].count := 0;
    c.slots[i].rcode := 0;
    c.slots[i].expiry := 0;
  end;
end;

function KeyMatch(const e: TDnsCacheEntry; const name: string; qtype: Integer): Boolean;
begin
  KeyMatch := e.used and (e.qtype = qtype) and (e.name = name);
end;

{ Find the slot for (name,qtype): an existing key, else a free slot, else the
  soonest-expiring slot (evicted). Always returns a usable index. }
function SlotFor(var c: TDnsCache; const name: string; qtype: Integer): Integer;
var
  i, freeIdx, oldestIdx: Integer;
  oldestExp: Int64;
begin
  freeIdx := -1;
  oldestIdx := 0;
  oldestExp := c.slots[0].expiry;
  for i := 0 to DNS_CACHE_SLOTS - 1 do
  begin
    if KeyMatch(c.slots[i], name, qtype) then
    begin
      SlotFor := i;
      Exit;
    end;
    if (not c.slots[i].used) and (freeIdx < 0) then
      freeIdx := i;
    if c.slots[i].expiry < oldestExp then
    begin
      oldestExp := c.slots[i].expiry;
      oldestIdx := i;
    end;
  end;
  if freeIdx >= 0 then
    SlotFor := freeIdx
  else
    SlotFor := oldestIdx;   { full — evict soonest-expiring }
end;

procedure DnsCachePut(var c: TDnsCache; const name: string; qtype: Integer;
  const ips: TDnsIpv4Array; count, rcode: Integer; nowMs, ttlMs: Int64);
var
  idx, i, n: Integer;
begin
  if ttlMs <= 0 then Exit;   { do not cache an already-dead answer }
  idx := SlotFor(c, name, qtype);
  c.slots[idx].used := True;
  c.slots[idx].name := name;
  c.slots[idx].qtype := qtype;
  n := count;
  if n < 0 then n := 0;
  if n > DNS_MAX_IPS then n := DNS_MAX_IPS;
  for i := 0 to n - 1 do
    c.slots[idx].ips[i] := ips[i];
  c.slots[idx].count := n;
  c.slots[idx].rcode := rcode;
  c.slots[idx].expiry := nowMs + ttlMs;
end;

function DnsCacheGet(var c: TDnsCache; const name: string; qtype: Integer;
  nowMs: Int64; var ips: TDnsIpv4Array; var count: Integer; var rcode: Integer): Boolean;
var
  i, k: Integer;
begin
  count := 0;
  rcode := 0;
  DnsCacheGet := False;
  for i := 0 to DNS_CACHE_SLOTS - 1 do
    if KeyMatch(c.slots[i], name, qtype) then
    begin
      if nowMs < c.slots[i].expiry then
      begin
        for k := 0 to c.slots[i].count - 1 do
          ips[k] := c.slots[i].ips[k];
        count := c.slots[i].count;
        rcode := c.slots[i].rcode;
        DnsCacheGet := True;
      end
      else
        c.slots[i].used := False;   { reap the expired entry }
      Exit;
    end;
end;

procedure DnsCachePut6(var c: TDnsCache; const name: string;
  const ips6: TDnsIpv6Array; count, rcode: Integer; nowMs, ttlMs: Int64);
var
  idx, i, k, n: Integer;
begin
  if ttlMs <= 0 then Exit;   { do not cache an already-dead answer }
  idx := SlotFor(c, name, DNS_TYPE_AAAA);
  c.slots[idx].used := True;
  c.slots[idx].name := name;
  c.slots[idx].qtype := DNS_TYPE_AAAA;
  n := count;
  if n < 0 then n := 0;
  if n > DNS_MAX_IPS then n := DNS_MAX_IPS;
  for i := 0 to n - 1 do
    for k := 0 to 15 do
      c.slots[idx].ips6[i][k] := ips6[i][k];
  c.slots[idx].count := n;
  c.slots[idx].rcode := rcode;
  c.slots[idx].expiry := nowMs + ttlMs;
end;

function DnsCacheGet6(var c: TDnsCache; const name: string; nowMs: Int64;
  var ips6: TDnsIpv6Array; var count: Integer; var rcode: Integer): Boolean;
var
  i, j, k: Integer;
begin
  count := 0;
  rcode := 0;
  DnsCacheGet6 := False;
  for i := 0 to DNS_CACHE_SLOTS - 1 do
    if KeyMatch(c.slots[i], name, DNS_TYPE_AAAA) then
    begin
      if nowMs < c.slots[i].expiry then
      begin
        for j := 0 to c.slots[i].count - 1 do
          for k := 0 to 15 do
            ips6[j][k] := c.slots[i].ips6[j][k];
        count := c.slots[i].count;
        rcode := c.slots[i].rcode;
        DnsCacheGet6 := True;
      end
      else
        c.slots[i].used := False;   { reap the expired entry }
      Exit;
    end;
end;

function DnsCacheLiveCount(var c: TDnsCache; nowMs: Int64): Integer;
var i, n: Integer;
begin
  n := 0;
  for i := 0 to DNS_CACHE_SLOTS - 1 do
    if c.slots[i].used and (nowMs < c.slots[i].expiry) then
      n := n + 1;
  DnsCacheLiveCount := n;
end;

end.
