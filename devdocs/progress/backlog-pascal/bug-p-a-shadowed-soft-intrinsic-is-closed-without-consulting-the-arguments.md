---
track: P
prio: 30
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-06
summary: "SoftIntrinsicOpen answers WHETHER a routine of an intrinsic's name is in scope and nothing about the call's arguments, so any same-named declaration closes the intrinsic for every argument shape -- including shapes it could never bind. Fixed for the bare-name dyn-array Delete/Insert case (DynArrayReopensIntrinsic, pasparser_stmt.inc); the general answer, and the non-bare spellings `Delete(obj.Items, i, 1)` / `Insert(x, p^.list, i)`, are still closed. Sixteen call sites share the predicate."
---

# A shadowed soft intrinsic is closed without consulting the arguments

- **Type:** bug — **Track P** (`compiler/symtab.inc` `SoftIntrinsicOpen` /
  `SoftIntrinsicOpenSym`, and their sixteen call sites in
  `compiler/pasparser_stmt.inc`, `_expr.inc`, `_lval.inc`).
- Found closing the dyn-array `Delete`/`Insert` wall on fcl-passrc rung 7
  (`pscanner.pp:5025`, `:5033`).

## The shape

`SoftIntrinsicOpen` is a Boolean:

```pascal
SoftIntrinsicOpen := (qUnit = -2) or
  ((FindProc(nm) < 0) and not IntrinsicShadowedByMember(nm));
```

It is asked BEFORE any argument is parsed, so it cannot be anything else — and
a Boolean forces its caller into an all-or-nothing decision. **The guard
answers WHETHER, not WHICH**, the same shape as
[[bug-p-two-array-parameters-at-one-bracket-slot-are-decided-by-declaration-order]].

The measured cost: `lib/rtl/sysutils.pas` declares
`Delete(var s: AnsiString; index, count)` and
`Insert(const src: AnsiString; var dst: AnsiString; index)` — two routines fpc
keeps in `system` and NOT in sysutils. One `uses sysutils` therefore took
dynamic-array `Delete` and `Insert` away from essentially every program in this
tree, with a diagnostic naming the string overload as the only candidate.

## What is already fixed

`DynArrayReopensIntrinsic` (`compiler/pasparser_stmt.inc`) reopens the
intrinsic when three things hold: the shadow is a free routine taking a plain
string at that parameter position (`IntrinsicShadowIsStringOnly`), no method of
the enclosing class shadows the name, and the argument is a BARE NAME that
resolves to a dynamic array from the tokens alone (`BareDynArrayArgAhead`).

## What is not

- **Non-bare spellings.** `Delete(obj.Items, i, 1)`, `Delete(p^.list, i, 1)`,
  `Insert(x, Self.F, i)` still take the shadow, because the token probe
  deliberately refuses anything it cannot resolve without the expression
  parser. `DynTargetIsRereadable` already names those exact shapes as the ones
  real code writes, so this is a real remainder and not a corner.
- **The other fourteen call sites.** `SetLength`, `New`, `Dispose`,
  `ReallocMem`, `Str`, `Inc`/`Dec`, `GetMem`/`FreeMem`, `Move`/`FillChar`,
  `Break`/`Continue`, `SysOpen`/`SysRead`/`SysWrite`. Each has the same
  all-or-nothing shape; none has been probed for a shadow that could not bind.
  **Enumerate from the concept, not from the callers** — the question is which
  RTL units declare a name that collides with an intrinsic, and
  `lib/rtl/sysutils.pas` alone also re-declares `Copy`, `UpCase` and `Pos`
  (those three were probed and do NOT diverge: dyn-array `Copy(a)`,
  `Copy(a,i,n)` and `Concat(a,a)` all match fpc with sysutils in scope,
  because they resolve in the expression parser on a different path).

## The other half of the fork

The RTL declarations are themselves the anomaly: fpc's sysutils has no
`Delete`/`Insert`, and the pxx ones are byte-for-byte the intrinsic's
behaviour (`__pxxStrDelete` / `__pxxStrInsert` in `compiler/builtin/`).
Deleting them from `lib/rtl/sysutils.pas` would remove this instance at the
source — but the builtin unit is not compiled for **ESP** targets
(`TargetIsEspClass` blocks the auto-`uses`), so on ESP the string spelling
would go from working to `Delete: string helper unavailable`. That trade is
Track B/S's to make and is NOT part of this ticket; it is recorded here so the
next reader does not re-derive it.

## Not a defect

A user routine that CAN bind the argument must still win, and does: fpc runs a
user `Delete(var a: TA; index, count)` and so do we. Verified in
`test/test_a_dynamic_array_delete_survives_a_string_delete_in_scope.pas`, whose
last row is that control. fpc REFUSES a dyn-array argument when only a string
`Delete` is in scope; we accept it, which is the benign direction.
