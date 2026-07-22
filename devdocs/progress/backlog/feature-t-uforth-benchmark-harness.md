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
