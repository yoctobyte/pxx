---
prio: 70
track: A
status: done
owner: frankS
---

> **Track corrected P -> A** (frankS): the test source is Pascal but the cause is in the shared core -- `AssignSideKind` in `ir.inc`, my own `fa8f2424d`. The guess reads the test; the cause was one layer under it.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_methodptr_nil_assign.pas red at dc798834ba33 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T18:15:54Z
- **Test source:** test/test_methodptr_nil_assign.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_methodptr_nil_assign.pas'` at dc798834ba33aee86e1af089a8e2579da57087e7

## Range
> **The named sha `dc798834ba33` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `dc798834ba33`, last good `fc9e258e1b71`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:46: error: incompatible types: cannot assign Pointer to record
pascal26:51: error: incompatible types: cannot assign Pointer to record
pascal26:58: error: incompatible types: cannot assign Pointer to record
(tail)
pascal26:46: error: incompatible types: cannot assign Pointer to record
pascal26:51: error: incompatible types: cannot assign Pointer to record
pascal26:58: error: incompatible types: cannot assign Pointer to record

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Diagnosis and fix (frankS, at HEAD)

**Cause: my own `fa8f2424d`**, which extended the assignment type check from
`AN_IDENT` to `AN_INDEX` / `AN_FIELD` / `AN_DEREF`. Both regressed lines are a
method pointer assigned `nil` through a non-identifier lvalue:
`c.OnHit := nil` (field), `arr[1] := nil` (element).

A method pointer is a 16-byte record `{Code, Data}`, so `dstTk = tyRecord`;
`nil` is `tyPointer`; `AssignKindsIncompatible`'s record rule refuses the pair.
The check is right to have an exemption and my arm had **half** of one: I
carried over the AN_IDENT arm's *interface* bail (an interface is also a
tyRecord fat pointer) and not the method-pointer one -- because the interface
half is the one that had shown up in a differential run, and the identifier arm
never needed the other half. A method-pointer VARIABLE exits earlier on
`SymProcSig >= 0`, for an unrelated reason. That accidental cover is why one
missing case survived until a second lvalue shape reached the same code.

**Fix:** `RecIsReferenceShaped(rec)` in `symtab.inc` -- the one place that knows
which record ids are really fat pointers (interface, method pointer). Three
call sites now ask it instead of spelling it: both `AssignSideKind` arms and
`ProcParamIsNilable`, which already had both halves and is where the concept was
already documented. Two is a smell, three is a design flaw.

**Verified at HEAD** (self-host fixedpoint `b69b9c33abbe`), both directions:
- `test_methodptr_nil_assign` and `test_nil_argument_positions` both compile and
  match their Makefile expectations byte for byte.
- The original bug `fa8f2424d` fixed is still caught: `test_assign_lvalue_shapes_fail`
  still produces exactly 12 refusals, `test_assign_lvalue_shapes_ok` still prints
  `lvok 16 a sh sh z 1 TRUE 7`.

The two tests in this ticket ARE the regression coverage for the method-pointer
half; no new test is needed for it.
- 2026-08-30 — resolved, commit d5fd2a6ca.

---

## Bisect (frank-rust, independent) — kept because it is the reason the predicate exists

Cause located **by building**, not by reading:

| binary | `test_methodptr_nil_assign.pas` |
| --- | --- |
| `fa8f2424d^` | **compiles** |
| `fa8f2424d` | **FAILS**, all three lines |

The only other buildable commit in Track T's range is `9588c8535` (string-literal
perf) and it is *newer*, so the range collapses to one commit. Both bisect
binaries were fresh self-host fixedpoints of the named tree, not the seed;
diagnosis at HEAD `38a9803b7`.

The asymmetry that bisect exposed is the argument for a named predicate rather
than a second inline pair: the `AN_IDENT` arm carried **two** bails against types
*spelled* `tyRecord` that are not records —

```pascal
  if SymProcSig[si] >= 0 then Exit;        { procvar: the kind is the RESULT's }
  ... UClsIsInterface[...] then Exit;      { an interface is a fat pointer }
```

— and the three new arms inherited the interface one and not the procvar one.
`fa8f2424d`'s own note one line down says it: *"the kind is not a reliable
description here, which is exactly what this function is for."* There were two
such types; the new arms learned one. That is why `RecIsReferenceShaped` is the
right shape and "restore the missing bail" was not: writing the pair out a second
time sets up the identical failure for whoever adds a third reference-shaped type.

## Verified independently at HEAD before closing

Binary `bb3a768b89a2`, a self-host fixedpoint at HEAD in the `frank-rust`
checkout — a different tree from the one the fix was written in:

```
hit 1 / var    assigned=FALSE
hit 2 / field  assigned=FALSE
hit 3 / elem   assigned=FALSE
varpar assigned=FALSE
loop ok
```

All four shapes re-armed, called, cleared, confirmed clear. Green. Agreed with
frankS that no new test is needed: this test already re-arms and CALLS each slot
before clearing it, so it proves the slot was live rather than proving
`Assigned()` is uniformly false — its red→green transition IS the measurement.

Two sessions reached the same mechanism from opposite ends within the hour and
the one that landed chose the better shape; recording that here so the diagnosis
is not lost with the duplicate ticket file.
