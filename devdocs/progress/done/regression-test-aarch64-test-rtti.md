---
prio: 70
track: A
status: done
---

> **Track A from the job NAME `test-aarch64`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/test_rtti.pas`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 13 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-aarch64#src:test/test_rtti.pas at 9d5a4e27029e in step 1/3, `./compiler/pascal26 -dPXX_MANAGED_STRING --target=aarch64 test/test_rtti.pas /tmp/test_aarch64_rtti` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T18:15:00Z
- **Test source:** test/test_rtti.pas tools/expect_same.sh +1
- **Failing step:** line 1 of 3 of the job's recipe; it names `test/test_rtti.pas`.
  ```
  ./compiler/pascal26 -dPXX_MANAGED_STRING --target=aarch64 test/test_rtti.pas /tmp/test_aarch64_rtti
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-aarch64#src:test/test_rtti.pas'` at 9d5a4e27029eb30dd509ad8ab8326b269a8b9af7

## Range
> **The named sha `9d5a4e27029e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `9d5a4e27029e`, last good `b040c90e6c8b`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

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
- 2026-09-04 — the seven watcher saw `test-aarch64#src:test/test_rtti.pas` GREEN at b8e3b3010249 (tier full) and did NOT close this: the job's class is `qemu`, which testmgr treats as runtime-nondeterministic (RUN_RETRY_CLASSES) — a single pass does not refute a red there. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

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
