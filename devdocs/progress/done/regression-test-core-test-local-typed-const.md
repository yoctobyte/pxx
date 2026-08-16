---
prio: 70
status: done
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_local_typed_const.pas red at 88b863e7c731 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-16T07:47:35Z
- **Test source:** test/test_local_typed_const.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_local_typed_const.pas'` at 88b863e7c7311d5f1da708ba3ce7bcfe172e09b3

## Range
bad `88b863e7c731`, last good `6891a4d56494`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:41: error: invalid IR symbol reference in load_sym
(tail)
pascal26:41: error: invalid IR symbol reference in load_sym
  near:  WriteLn  SumTable   >>> end  unit 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## RESOLVED 2026-08-16 (Track P) — mine, fixed forward in 467a4e5da

Caused by `3ed3e2653` (routine-local typed consts made static). Two faults, the
second only reachable once the first was fixed:

1. `SymRollbackTo` reclaimed the const's symbol index when the routine ended,
   and the **-O2 inliner** then copied the body into the caller, where the copy
   still loads it — verified after the rollback, one past the end. That is the
   `invalid IR symbol reference in load_sym` this ticket recorded. `-O0`/`-O1`
   were clean, which named the inliner.
2. Fixing the index exposed a **silent wrong value** at -O2 (`Scaled(6)` gave 0,
   not 42): the run-once prologue guard is skipped by an inlined copy, so the
   initialisation never ran.

`SymRollbackTo` now keeps its high-water mark above a `SymStaticLocal` symbol
(still unhashing it), and the initialiser is an ordinary `PendingInit` row
emitted once before `main begin` — no prologue for the inliner to skip.

Verified: this test and `test_local_typed_const_is_static.pas` both pass at
-O0/-O1/-O2/-O3 and match `fpc -O- -Mobjfpc`. Full write-up in
[[bug-p-a-routine-local-typed-const-is-reinitialised-on-every-call]].
- 2026-08-16 — resolved, commit d594272ef.
