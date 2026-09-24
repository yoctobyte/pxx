---
prio: 25
summary: "NO LONGER REPRODUCES, re-measured 2026-09-24 (frankS). sqlite3.c (-DSQLITE_THREADSAFE=0 --emit-obj, 4524 procs) compiles in 8.0s, min of 3, against 32.2s for 4049 procs on 2026-07-08: about 563 procs/s against 131. A synthetic scaling series of 1000/2000/4000/8000 uniform C functions is flat at 1.25/1.13/1.07/1.11 s per 1000 functions, best of 3, so there is no superlinear term on that population. The July comparison was lua against sqlite; lua is not on this box, so that pair was not re-run, and both rows are carried below."
track: C
status: done
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

## 2026-09-24 (frankS): re-measured, closed

Both rows are carried, each with its population. The July row is not refuted;
it described a different tree.

| date | subject | measurement |
| --- | --- | --- |
| 2026-07-08 | sqlite3.c, 4049 procs, native | 32.2s total (131 procs/s) |
| 2026-09-24 | sqlite3.c, 4524 procs, `-DSQLITE_THREADSAFE=0 --emit-obj`, compiler ec3d2325ef7b | 8.0s, min of 3 (8.03/8.12/8.23), about 563 procs/s |
| 2026-09-24 | synthetic: N functions, each one global, one struct-pointer param, a loop and a call to its predecessor, N = 1000/2000/4000/8000, full executable | 1.25 / 2.26 / 4.28 / 8.90 s, i.e. 1.247/1.130/1.069/1.112 s per 1000 functions |

The per-function cost is flat across an 8x range, so there is nothing
superlinear to find on this population. What would reopen it: a real program
whose per-proc compile cost grows with the size of the translation unit.
Measure that with a series on its OWN code, not a single pair of files, since
the July pair compared two different programs.

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
