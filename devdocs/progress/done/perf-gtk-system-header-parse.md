---
prio: 45
---

# perf: real GTK2 system-header import is ~20s / 13619 procs — flaky-timeout candidate

- **Type:** parse performance. Track A (the cost is in shared `cpreproc.inc` /
  `parser.inc` / `cparser.inc` header import, not a single frontend).
- **Found:** 2026-07-08, while resolving `regression-cfront-stmt-expr-25c1dded`.

## Problem
`test/test_c_gtk.pas` does `uses gtk`, which resolves to the real system
`/usr/include/gtk-2.0` headers (enabled by `c44dd55e`). Compiling that trivial
5-line program pulls **13619 procs** and takes **~17–40 s** wall on a dev box —
the time is dominated by header preprocessing/parsing (emitted code is tiny and
byte-identical regardless of frontend churn).

This is long-standing (predates the stmt-expr commit that got wrongly blamed for it),
but it is a real flakiness source: `test-core#599`/`#601` (the GTK header units) can
cross testmgr's 90 s per-unit timeout under parallel full-tier load and report a
TIMEOUT with an empty log. It already flapped RED→GREEN across borg runs on timing
alone.

## Asks
1. Profile the GTK2 header import and cut the parse cost (13619 procs for a header
   import is heavy — candidate: preprocessor temp-string churn, symbol-hash-chain
   growth on the many typedef'd names, redundant re-parsing).
2. Give these units a **scaled per-unit timeout budget** in testmgr so a slow-but-
   correct header import can't silently masquerade as a regression. Target from the
   parent ticket: GTK header tests < 5 s at scale 1 (aspirational; set the budget to
   reality until the parse is optimized).

## Resolved 2026-07-08 (cfront-agent) — root cause was an O(n²) in the C preprocessor
Profiled the ~40s `test_c_gtk.pas` compile: **33.7s was in `CPreprocess` alone**
(parse + codegen < 1s). `CPrepOut` accumulated the whole ~MB output one char at a
time via `AppendChar`→`SetLength(len+1)`, and PXX's `SetLength` always reallocs to
the exact size (no spare capacity) → every char copied the entire output so far.
Fixed in `d531804e`: `CPrepOut` now grows geometrically (capacity in its physical
`Length`, live count in `CPrepOutLen`), trimmed once at the end; each line expands
into a small scratch then amortized-appends.
- `--dump-cpp` output **byte-identical**; GTK2 preprocess **33.7s → 6.7s**, full
  `test_c_gtk.pas` compile **~40s → 9.8s** — comfortably under the testmgr unit
  deadline (was TIMEOUT). Self-host fixedpoint byte-identical; C conformance
  212/0/8; cjson/lua/quick green.
- Cured the flaky-TIMEOUT on `test-core#599/#601/#602` (all four gtk header units).
- Residual (optional, low prio): remaining ~6.7s preprocess + ~3s parse/codegen of
  the 13619 procs is real header size, not a quadratic. A macro-lookup or
  symbol-hash pass could shave more toward the <5s aspiration, but the regression
  risk (deadline TIMEOUT) is gone. Not filing a follow-up unless it flakes again.

## Gate
GTK header units compile well under the per-unit timeout at full-tier scale; no
change to emitted code (byte-identical); self-host fixedpoint unaffected. **Met.**

## Log
- 2026-07-08 — resolved, commit d531804e.
