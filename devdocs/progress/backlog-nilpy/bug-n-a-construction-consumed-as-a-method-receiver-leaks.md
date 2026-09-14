---
type: bug
track: N
prio: 80
status: open
slug: bug-n-a-construction-consumed-as-a-method-receiver-leaks
---

# `Quat(...).normalized()` leaks the construction, and the obvious fix segfaults the demo

A NilPy construction consumed as a METHOD RECEIVER is never released. One
instance per call, forever. `Quat(1,0,0,0).normalized()` -- the ordinary
spelling of fluent vector maths.

Measured 2026-09-14 against pin v410 and against HEAD, CPython oracle 0 for
every row:

| shape | leaked per call |
|---|---|
| `P(1, 2).sum()`  -- method on a temporary | **1 instance** |
| `P(1, 2)` as a bare statement             | **1 instance** |
| `p = P(1, 2)`                             | 0 |
| `P(1, 2).a` -- ATTRIBUTE on a temporary   | 0 |
| `f(P(1, 2))` -- argument                  | 0 |
| `[P(), P()]` / `{k: P()}`                 | 0 |
| `return P(1, 2)`                          | 0 |
| `Q(...) * s` -- operand of an operator    | 0 |

So an assignment, an argument bind, a container store, a return and an operand
all drop the construction's rc=1 correctly. A METHOD RECEIVER and a DISCARDED
STATEMENT do not.

## THE MECHANISM IS ALREADY DOCUMENTED, INCLUDING THE GAP

`compiler/defs.inc` (`SymIsCtorResultTemp`): the conduit local *"holds the
construction's rc=1 for whoever consumes the expression and never releases
it"*. `compiler/ir.inc`'s arg-spill arm owns that rc=1 for every ARGUMENT
position and excludes param 0, and its own comment names the gap:

> Param 0 (a method receiver) is excluded: the for-in and method desugars route
> the SAME construction subtree through receiver position with their own binding
> plumbing, and spilling it there double-consumed the construction
> (test_nilpy_forin SIGSEGV). **A bare `[...].method()` receiver still leaks --
> rare shape.**

**It is not a rare shape.** lekkerzeilen has four sites, all on the physics
path, all inside per-frame or per-sim-step functions (math3d.py:168, 199, 201;
vessel.py:471). At 120 Hz it was the largest single producer in that demo's
leaked-object histogram: 880,508 unfreed 40-byte objects in 300 s, 73% of the
total, where 40 bytes is exactly `Quat`'s instance size.

**A module-level loop leaks NOTHING and a function-scope loop leaks every
time.** The two lowerings differ. Measure inside a `def` or you will measure
zero and conclude it is fixed.

## THE OBVIOUS FIX PASSES 963 TESTS AND KILLS THE DEMO IN 3 SECONDS

Extending the arg-spill arm to param 0 for the user-class-NEW shape only
(patch parked at the end of this ticket) measures perfectly:

* the repro goes to 0 leaked, correct output
* `make test-nilpy` -- the whole Track N lane gate, 963 fixtures -- **GREEN**
* the specific historic hazard probed directly on eight desugar shapes against
  CPython, including `for x in Bag(4)` (a user-class construction in exactly
  the excluded receiver position): all match

and then lekkerzeilen SIGSEGVs after 3.0 s of frame loop, deterministically.

The 2x2 that establishes it, one compiler axis and one builtin axis, all
`--open-water`, back to back on a quiet box:

| compiler | builtin at e4c72bd15 | builtin at 17e5731a7 |
|---|---|---|
| HEAD `44a0066` | survives 87.2 s (to timeout) | survives 87.2 s |
| HEAD + this patch | **SIGSEGV, in-loop 3.00 s** | **SIGSEGV, in-loop 2.99 s** |

The builtin is not the variable. The patch is.

### WHERE IT DIES

`PyCallablePartsP+0x52` (pylib.pas), reading `p^.VType` -- i.e. the PPyVarRec
the caller handed it is itself a dangling pointer. The compiled bytes of that
function are **byte-identical** in the crashing and surviving binaries, so it is
a LIFETIME bug and not a miscompile. A callable variant is a `{code, recv}` pair
block; the spill is releasing something a live callable still points at.

### WHAT THIS SAYS ABOUT THE LANE GATE

963 fixtures green, one real program dead in three seconds. `make test-nilpy`
does not cover object lifetime across a long-running frame loop, and nothing in
it holds a bound method across statements the way an application does. **Do not
take a green Track N tier as evidence for a refcounting change.** Build the demo
and run it -- `--open-water` reaches the frame loop in ~3 s.

## WHAT A REAL FIX PROBABLY LOOKS LIKE

The receiver's ownership belongs to the METHOD-CALL lowering, which knows
whether it borrows or consumes, not to the argument spill, which does not.
Making the arg spill own param 0 for every callee is what breaks it -- the
`ProcRetRecId` arm beside it is explicitly scoped to *"free functions, not
methods"* for this reason and the parked patch ignores that distinction.

## THE PARKED PATCH

`compiler/ir.inc`, the NilPy construction-in-argument spill: replace the
`(pathIdx >= 1)` guard on the construction arm with one that also admits
pathIdx 0 when the arg is a user-class NEW:

```pascal
       ( { user-class NEW allowed at pathIdx 0 too }
         (((Integer(ASTIVal[argAST]) = -Ord(tkGetMem)) and
           (Integer(ASTRight[argAST]) >= REC_UCLASS_BASE)))
         or ((pathIdx >= 1) and (IntToTypeKind(ASTTk[argAST]) = tyClass)) )
```

Do not land it as-is. It is recorded so the next session does not spend the
evening re-deriving a change that measures clean everywhere except in a running
program.

## REPRO FOR THE LEAK ITSELF

`test/test_nilpy_a_user_object_does_not_leak_because_of_how_its_value_is_consumed.npy`
carries a `ctor_recv` row that asserts this leak DELIBERATELY, as a positive
control. When this ticket is fixed that row goes red and the fixture says, in
its own output, to flip it.
