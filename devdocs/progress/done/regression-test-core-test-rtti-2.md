---
prio: 70
track: P
status: done
---

> **Track guessed as P from the FAILING STEP** — line 1 of 5, `./compiler/pascal26 test/test_rtti.pas /tmp/test_rtti26`, which names `test/test_rtti.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 1 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_rtti.pas at 31f8b11bfddf in step 1/5, `./compiler/pascal26 test/test_rtti.pas /tmp/test_rtti26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T17:55:14Z
- **Test source:** test/test_rtti.pas
- **Failing step:** line 1 of 5 of the job's recipe; it names `test/test_rtti.pas`.
  ```
  ./compiler/pascal26 test/test_rtti.pas /tmp/test_rtti26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_rtti.pas'` at 31f8b11bfddf7e179bc7961abcd4ee64eb3441bf

## Range
bad `31f8b11bfddf`, last good `b040c90e6c8b`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:144: error: no overload of SetMethodProp matches these arguments
(tail)
pascal26:144: error: no overload of SetMethodProp matches these arguments
  argument types: (Pointer, Pointer, record)
  candidates:
    SetMethodProp(Pointer, Pointer, record)
  near: ) , p , meth ) >>> ; meth := 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-04 — the seven watcher saw `test-core#src:test/test_rtti.pas` GREEN at 035ded7723d1 (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-rtti-2`, not `regression-test-core-test-rtti`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

---

## Resolved — fixed at the root by `a623307bd`, verified green at HEAD (frankB, 2026-09-05)

**Cause.** The bisect range held exactly ONE buildable commit: `31f8b11bf`
*"feat(P): System.TMethod, and furnish Result with its return type's procedural
signature"*. It introduced a builtin `System.TMethod` while the RTL still
declared its own, so `SetMethodProp` saw two distinct records — which is why the
diagnostic refutes itself:

```
error: no overload of SetMethodProp matches these arguments
  argument types: (Pointer, Pointer, record)
  candidates:
    SetMethodProp(Pointer, Pointer, record)
```

The argument list and the only candidate print IDENTICALLY. Overload resolution
was right and the message could not say so, because two different records both
render as `record`. **Worth keeping as a diagnostic-quality example**: a
type-identity mismatch that prints as a tautology tells the reader nothing about
which of the two types they have.

**Fix.** `a623307bd` *"fix(P,B): System.TMethod is declared once — delete the RTL
duplicates, and let a UNIT see the builtin"* — the root cause, not a signature
patch. Track T's own watcher recorded both ends: `e480b1bcc` filed
`NEW-RED:test-core#src:test/test_rtti.pas`, `c35655e82` recorded
`FIXED:test-core#src:test/test_rtti.pas` on native, and `b668ba503` recorded
`FIXED:` for `test-aarch64`, `test-arm32`, `test-i386` and `test-xtensa`
together. One cause, five jobs, one fix.

**Verified at HEAD**, compiler `47618f77c240` (built `converged after 1 round(s)`,
not the stamp path), every step of BOTH jobs run rather than only the step the
ticket names:

```
test-core#src:test/test_rtti.pas          5/5 steps  compile, run, 3 greps
test-aarch64#src:test/test_rtti.pas       3/3 steps  aarch64 compile, x64 control, expect_same
```

The aarch64 comparison was checked for the empty-output trap before being
believed: both sides are **388 bytes**, so `expect_same` had real inputs on both
arms rather than passing on `'' = ''`.

**Not closed by inspection.** These two tickets and the three targets in that
`FIXED:` line share one cause, so re-verifying one and reasoning about the rest
would have been the cheap version; the cross row was run because a cross target
is exactly where a native-only green stops generalising.
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
