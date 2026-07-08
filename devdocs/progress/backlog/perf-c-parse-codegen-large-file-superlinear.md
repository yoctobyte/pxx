---
prio: 30
---

# perf: C parse+codegen shows mild superlinear scaling on very large amalgamations

- **Type:** perf (parse/codegen throughput) — Track A (shared cparser→IR / symtab /
  ir_codegen; not a single frontend).
- **Found:** 2026-07-08, profiling after the GTK preprocessor O(n²) fixes
  (`d531804e`, `fa5d160f`). Not causing any test failure — informational.

## Data (native, current compiler)
- **sqlite3.c** (257670 src lines): preprocess **0.56s**, total compile **32.2s**,
  4049 procs → the ~31.6s balance is all parse + IR + codegen + ELF.
- **lua** runner (full amalgamation): total **7.94s**, 1571 procs.
- Throughput: lua ≈ 198 procs/s, sqlite ≈ 131 procs/s. At 2.6× the procs sqlite
  takes ~4× the time — a linear extrapolation from lua predicts ~20s, actual 31.6s.
  So ~1.5× worse than linear: a mild superlinear component, not a hard O(n²).

## Not urgent
No timeout/failure — `test-sqlite-threads` and friends have generous deadlines and
pass. The preprocessor quadratics that *did* cause the Track T flaky-timeouts are
already fixed. This ticket only records the finding so a future perf pass has a
starting point.

## Where to look (unprofiled — needs a phase timer)
Split the ~31.6s across parse vs IR-build vs codegen vs ELF first (no phase timing
exists today; add coarse timers around ParseCProgram / IR / codegen / writeELF).
Candidate weak-quadratics for a large single translation unit: any per-global or
per-proc pass that scans all prior globals/procs (O(n²)), forward-reference/fixup
resolution, or a linear scan keyed by count that the symbol hash doesn't cover.

## Gate
Emitted code byte-identical; self-host fixedpoint unaffected; measurable throughput
improvement on sqlite3.c.
