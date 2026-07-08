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

## Gate
GTK header units compile well under the per-unit timeout at full-tier scale; no
change to emitted code (byte-identical); self-host fixedpoint unaffected.
