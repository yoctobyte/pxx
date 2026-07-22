---
track: T
prio: 45
type: feature
---

# Track T: uforth benchmark harness — pxx-compiled vs interpreted Python baselines

## Idea (user-requested)

uforth is a real, non-trivial NilPy program with a large deterministic
workload (the Forth-2012 suite + microbenches), which makes it the natural
speed oracle for the NilPy backend: the SAME uforth.py runs

1. **plain interpreted Python** — `python3 uforth.py` (the CPython
   interpreter running the source),
2. **CPython** baseline variants as useful (e.g. `python3 -O`, and a PyPy
   column if installed — cheap to add, big JIT reference point),
3. **pxx** — `pascal26 uforth.py` compiled native.

Same stdin scripts, wall-clock + max-RSS per runtime, speedup table.

## Workloads

- The suite drivers already used for conformance (prelim, core.fr,
  localstest, filetest, …) — real mixed workload.
- The DO/LOOP shift/and/xor microbench from the promoint fast-path work
  (10k iterations) — pure interpreter-dispatch hot loop.
- blocktest's ELF-HASH section — the known ~100x-slow outlier; a tracked
  number keeps the regression visible and measures future Track O wins.

Current known figure for context: pxx-compiled uforth ≈ 9x slower than
CPython on prelim (2026-07-21); fast paths took the DO/LOOP microbench
from 31s to 7.5s.

## Ownership / shape

Track T owns the TOOL (a `tools/` bench script or a testmgr bench tier —
T's call; the borg already has a `bench` job shape to hang rows on).
Findings are NOT fixed under T: a slow path goes to Track O (implicitly A)
or N as a ticket, per "T owns the tool, never the bug". Needs uforth
checked out (path configurable, default ~/projects/uforth); skip cleanly
when absent or when python3/pypy is missing. Keep runs bounded — a
--quick mode without ELF-HASH for routine runs, the full set for nightly.

## LANDED 2026-07-22 — tools/uforth_bench.py (f783cd25)

Standalone harness (T's call over a testmgr tier: the cross-runtime shape does
not fit the pxx-vs-FPC bench face). `make bench-uforth` [`BENCH_FULL=1`].

- **Runtimes:** cpython, cpython-O, pypy-if-present, pxx-native.
- **Workloads:** microbench-doloop, prelim (prelimtest.fth), core
  (tester.fr+core.fr concatenated — the suite pieces THROW -13 without the
  TESTING preamble), blocktest-elfhash (full only).
- **Source = GitHub** (git@github.com:yoctobyte/uforth): fetches origin, warns
  when the checkout is behind, and stamps the uforth sha into every bench.tsv
  row (7th column) so a number is tied to a specific source.
- **Quality:** min wall over N clean runs, descheduled runs discarded
  (wall>cpu*1.4); max-RSS from the child rusage via wait4. Skips cleanly when
  uforth/python3/a usable pxx is absent; a workload the base runtime can't run
  is SKIPped with a reason, not emitted as partial rows.
- **Must use the CURRENT compiler** — pinned stable can't lex uforth's
  char-code literals (`empty char-code literal after #`); default --pxx is the
  repo compiler, `make bench-uforth` passes ./$(COMPILER).

### First numbers (noisy — box under concurrent full-tier load)
| workload | cpython | pxx | speedup | pxx RSS |
| --- | --- | --- | --- | --- |
| microbench-doloop | ~5.6s | ~17.8s | 0.31x (3.2x slower) | 582 MB |
| prelim | ~0.43s | ~1.77s | 0.24x | 32 MB |
| core | ~0.89s | ~5.1s | 0.17x | 166 MB |

pxx is 3-6x slower and 5-24x the RSS on these — **Track O findings, filed
there, not fixed under T**. The 582 MB microbench RSS is the standout (the pxx
runtime/GC footprint on a tight loop). Consistent with the ticket's prior
"≈9x slower on prelim" ballpark; fast paths already took DO/LOOP 31s→7.5s.

### Follow-ups (filed, not blocking)
1. **ELF-HASH workload** — blocktest.fth needs uforth's block-word preamble
   (FIRST-TEST-BLOCK / LIMIT-TEST-BLOCK / `[?IF]`) that tester.fr alone does not
   provide, so blocktest-elfhash currently SKIPs. Assemble that preamble, or
   extract the ELF-HASH section as a standalone snippet, to restore the tracked
   ~100x outlier.
2. **Daemon idle-bench integration** — the harness is standalone + a make
   target today. Hanging it off the watcher's idle `bench` phase (so uforth
   rows land per-sha automatically) is a separate step; the row schema already
   matches bench.tsv.
3. **Run on a quiet box** for a clean baseline — the numbers above were taken
   while the full-tier daemon was running; re-baseline when idle.

## Reading the numbers (user, 2026-07-22) — these are GOOD, not a slowness flag

The pxx-vs-CPython ratios must NOT be read as "pxx is slow". uforth is a Forth
VM built on heavy dynamic dispatch — `exec()` (uforth.py:1289), ~17
exec/eval/getattr sites, PYTHON-bodied words compiled and run dynamically. That
is close to the worst case for an AOT compiler and close to the best case for
CPython, whose decades-tuned C eval loop (and, on newer builds, its JIT) is
exactly built to chew through this shape.

**And it is heavier than uforth.py alone suggests (user, 2026-07-22):** the
.UFO stdlib is itself full of dynamic bodies — **141 PYTHON-bodied words across
all 10 .UFO files** (1964 lines), compiled and `exec`'d on EVERY run during
startup, before the workload begins. So a short workload like prelim (279 ms)
is largely stdlib-load time dominated by exec'd Python bodies. The dynamic
surface pxx must route through its Python-body path is far larger than the
uforth.py `exec()` sites alone — which makes staying within ~6x of CPython on
these runs a stronger result still.

So on that terrain:
- **core 0.16x / prelim 0.17x** — within ~6x of CPython on a dynamic-dispatch-
  heavy REAL program is a strong result, not a gap to close.
- **microbench-doloop 0.43x** — on the tight interpreter loop, within ~2.3x of
  CPython. Very good; this is the path the promoint fast-paths already target
  (they took it 31s→7.5s earlier).

The one real follow-up is **memory**, not speed: pxx peak RSS is 582 MB on the
microbench vs CPython's 24 MB (~24x). That is the pxx runtime/GC footprint on a
tight loop and the thing worth looking into later — filed as [[bug-a-runtime-variant-heap-grows-unbounded]] (the memory
item), NOT as a speed regression.

**Claims discipline for any public copy:** if these ever appear in
docs/website, frame them honestly — "competitive with CPython on a
dispatch-heavy Forth VM" is fair; "as fast as CPython" is not (it is 0.16-0.43x
here), and the numbers are workload-specific. State the workload and that pxx
AOT-compiles a program whose hot path is dynamic dispatch.
