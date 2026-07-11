---
prio: 54  # auto — silent managed-string corruption from a unit-graph position; blocks clean cache wiring
---

# Transitive `uses dns_cache` corrupts managed-string codegen in an importer

- **Type:** bug (frontend/codegen — unit compilation / managed strings)
- **Track:** A. Filed from Track B (dns cache wiring) — hand off, do not fix
  under B/E.
- **Status:** done
- **Owner:** trackA-e-bugs

## Symptom
Adding `dns_cache` to the `uses` clause of `lib/rtl/dns_async.pas` — with **zero
references** to any dns_cache symbol — makes `test/lib_http.pas` (which
transitively imports dns_async) **segfault**, and before crashing its URL-string
tests return wrong results (`url-ok=FAIL`, `url-host=FAIL`, `url-path=FAIL` — the
managed-string `HttpParseUrl` output is corrupted). Removing the one `uses`
entry restores all 83 http checks. Reproduced deterministically at pinned v197.

So a unit merely appearing in the import graph — not any code that runs —
changes codegen for an unrelated importer's managed strings.

## What does / doesn't trigger it (bisected)
- **Triggers:** `uses ... dns_cache` inside `lib/rtl/dns_async.pas`, then build
  `test/lib_http.pas` (`http` → `dns_async` → `dns_cache`, and `http` also uses
  `dns_wire_core` directly — a diamond). → segfault, url tests corrupted.
- **Does NOT trigger:**
  - Program-level `uses http, dns_cache` doing the same `HttpParseUrl` (v3) —
    fine.
  - A trivial intermediate unit `umid` that `uses dns_cache`, imported by a
    managed http program (v5) — fine.
  - `{$define PXX_MANAGED_STRING}` program with `uses dns_cache` + heavy string
    concat, even declaring a `TDnsCache` local (v1) — fine.
- So it is specific to dns_cache sitting **inside dns_async** (a substantial
  unit) within http's real dependency graph — a transitive-import /
  unit-compilation-order codegen interaction, not the bare import.

## dns_cache's shape (likely relevant)
`dns_cache` declares `TDnsCacheEntry` = a record with a `string` (managed) field
plus a `TDnsIpv4Array`, gathered into `TDnsCacheSlots = array[0..63] of
TDnsCacheEntry` inside `TDnsCache`. Managed-string fields inside a record inside
a fixed array is the unusual construct; pulling that type through the dns_async
import likely perturbs the managed-string init/RTTI tables the importer emits.

## Workaround in place (Track B)
The cache-consuming resolver was moved to its own unit `lib/rtl/dns_cached.pas`
(`uses dns_cache, dns_async, ...`); `dns_async` (and thus `http`) does **not**
import `dns_cache`. Apps opt into caching by importing `dns_cached`. Everything
stays green, but a program that needs BOTH managed-string `http` and
`dns_cached` in one image will re-hit this until it is fixed.

## Gate
`make test` + self-host byte-identical; add the http-vs-dns_cache import case as
a regression (build a managed-string program through the http→intermediate→
dns_cache graph and check URL parsing + no fault).

## Resolution (2026-07-11)
Root cause was not unit compilation order at all: `AllocParam` / `AllocVar` /
`AllocDynArray` / `AddConst` never reset `SymArrNDims` on a recycled symbol
slot (symbol slots are reused after a proc body restores SymCount). A 2-D
local elsewhere in the graph left `NDims=2` in its slot; `dns_async`'s
`const ns: TDnsIpv4Array` param later landed on that slot and indexed with the
stale N-D dims — stride 64 instead of 4. The extra `uses dns_cache` merely
shifted global symbol allocation by one, aligning the param with the stale
slot; ANY interface const in the unit reproduced it. Fixed by resetting
`SymArrNDims` in all four Alloc paths (AllocArray already did). Regression:
`test/test_symslot_stale_ndims.pas` reproduces the slot-recycling directly
(pinned v197 prints 1, fixed prints 136) — deterministic, unlike the
alignment-dependent http graph. Track B may now revert the dns_cached
workaround and import dns_cache from dns_async directly if preferred.

## Log
- 2026-07-11 — resolved, commit ab7924ad.
