---
prio: 70
status: done
track: P
type: regression
summary: "RESOLVED. A real regression from 3ed3e2653 (routine-local typed const made static): a SCALAR local const read in an expression stopped compiling — invalid IR symbol reference in load_sym — while the array shapes and the counter idiom the fix targeted both worked. Bisected by Track T; root cause was SymRollbackTo handing the index back and the -O2 inliner still loading it. Fixed in 467a4e5da, carried by pin v342."
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

## Triaged and RESOLVED 2026-08-16 by Track T (face 2)

A **true regression**, not a flake, and bisected rather than guessed.

`3ed3e2653 fix(P): a routine-local typed const is static, initialised once` is
the commit. Built its parent and ran the test:

```
3ed3e2653~1   compiles, prints  100 a b c 42 100     <- correct
3ed3e2653..   pascal26:41: error: invalid IR symbol reference in load_sym
```

### What the fix got right, and what it broke

Worth separating, because the fix was not simply wrong — it achieved its target
and regressed a neighbour:

| shape | after `3ed3e2653` |
| --- | --- |
| `const calls: Integer = 0; Inc(calls)` — the counter idiom it was FOR | fixed: `1 2 3`, was `1 1 1` |
| `const T: array[0..3] of Integer = (...)` read by index | still fine |
| `const W: array[1..3] of Char` read by index | still fine |
| **`const Factor: Integer = 7;` read in an expression** | **compile error** |

So the scalar-read arm was the casualty, and the array arms were not — which is
the opposite of what the error text ("invalid IR symbol reference") suggests to
someone assuming an array-indexing problem.

### Root cause (Track P, reported after the bisect)

The symbol index did not die with the routine: `SymRollbackTo` handed the
const's index back, and the **-O2 inliner** then copied the body into the
caller, where the copy still loaded it — one past the end after the rollback.
`-O0`/`-O1` clean, `-O2`/`-O3` red, which named the inliner without guessing.
Fixing that exposed a second, worse defect underneath: a **wrong value** at -O2
(`7` became `0`), because the run-once prologue guard is invisible to a caller
that pasted the body, so the initialisation never ran and the BSS slot stayed
zero. A compile error became a silent wrong answer.

Fixed in `467a4e5da`, carried by **pin v342** (`315a0f77e`).

### Verified at HEAD

```
tools/testmgr.py --tier native --job 'test-core#src:test/test_local_typed_const.pas'
  PASS  test-core#756  unit  0.5s
  testmgr: GREEN
```

and the three minimised shapes above all compile and print correctly
(`42`, `b`, `8 9`).

### Filing note — third auto-filed stub today needing a hand-set `track:`

Same as [[regression-lib-test-crtl-reachability]] and
[[regression-test-core-test-strict-overload-width]]: twatch emits only `prio:`,
so a stub about a Pascal test ranks in **Track T's** queue until a human moves
it. Three in one day is a pattern, not an accident — twatch should guess a
`track:` from the test path when it files.
