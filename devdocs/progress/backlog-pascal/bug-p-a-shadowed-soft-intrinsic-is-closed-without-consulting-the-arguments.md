---
track: P
prio: 30
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-06
summary: "SoftIntrinsicOpen answers WHETHER a routine of an intrinsic's name is in scope and nothing about the call's arguments, so any same-named declaration closes the intrinsic for every argument shape. THE LIVE INSTANCE IS GONE AS OF 2026-09-09 AND THIS TICKET IS NOW ABOUT THE LATENT SHAPE ONLY -- re-measured at 69a5f3c6f, binary 5d5dcb45d328. Both halves of the fork this ticket described landed independently: the compiler reopens the intrinsic (f5ad23c32, 906737db0) and Track B removed the declarations (475528dae, 'sysutils must not declare the two names fpc keeps in system'). All three non-bare spellings this ticket listed as STILL CLOSED now work -- Delete(obj.Items,i,1), Delete(p^.list,i,1), Insert(x,Self.F,i) -- and the ESP risk the fork carried did not materialise: string Delete/Insert with sysutils in scope still gives fpc's answer. Enumerating from the concept rather than the callers, as this ticket instructs: NO free routine in lib/rtl re-declares any soft intrinsic today. The Delete/Insert/Move hits in classes.pas and contnrs.pas are METHODS, which FindProc does not see. What remains is a Boolean that cannot express WHICH, with no live instance."
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

## 2026-09-09 — re-measured: the live instance is gone, the shape is not

Verified at commit `69a5f3c6f`, binary `5d5dcb45d328`, `converged after 1
round(s)` (the stamp was removed and the build forced, because `make` had
printed `verified` with nine build inputs moved).

**The "What is not" section above is now false and is kept for the record.**
All three spellings it named as still closed:

```
Delete(b.Items, 1, 1)    len 3 -> 2    OK
Delete(p^.list, 1, 1)    len 3 -> 2    OK
Insert(9, Self.F, 1)     len 3 -> 4    OK
```

**Both halves of the fork landed, independently and by different tracks.** The
compiler side reopened the intrinsic (`f5ad23c32`, then `906737db0` for
`Insert`'s element list). Track B took the other half this ticket had explicitly
handed them — `475528dae`, *"sysutils must not declare the two names fpc keeps
in system"* — so the source-level anomaly is gone too.

**The ESP risk that fork carried did not materialise.** This ticket warned that
removing the sysutils declarations would take `Delete`/`Insert` from ESP string
code. Measured: `Delete(s,2,3)` then `Insert('XY',s,2)` on `'abcdef'` with
sysutils in scope gives `aXYef`, which is fpc's answer. The committed control
`test_a_dynamic_array_delete_survives_a_string_delete_in_scope` still matches
its `.expected`.

## Enumerating from the concept, which is what this ticket asked for

The question this ticket poses is *"which RTL units declare a name that collides
with an intrinsic"*. Answered by measurement rather than by reading callers:

**No free routine in `lib/rtl/*.pas` re-declares any soft intrinsic today** —
not `Delete`, `Insert`, `SetLength`, `New`, `Dispose`, `Str`, `GetMem`,
`FreeMem`, `FillChar` or `Move`.

**And the first attempt at that census was wrong in the direction this repo
keeps finding.** A grep for `^\s*(procedure|function)\s+Delete\s*\(` reports
`classes.pas` and `contnrs.pas`, which reads as *"the collision moved"*. Those
are **METHODS** — indented, inside class declarations — and `FindProc` does not
see them. Anchoring at column 1 returns nothing at all. The grep did not error;
it answered a question about text when the question was about free routines,
and the wrong answer was the interesting-looking one. Probing the six shapes
directly (`uses classes` / `uses contnrs` with dyn-array `Delete`, `Insert`,
`Move`) confirms every intrinsic stays open.

## Disposition — deliberately NOT re-ranked here

What survives is the SHAPE: `SoftIntrinsicOpen` is still a Boolean, still asked
before any argument is parsed, and `IntrinsicShadowIsStringOnly` remains the
narrow "which, not whether" patch beside it. That is real and it is now
**latent** — the exposure is a USER program declaring a colliding routine that
cannot bind, and a user routine that CAN bind must still win, and does.

Left at its current prio rather than demoted on one session's reading. A reader
deciding between `low-prio/` and the fourteen-call-site overhaul should know the
measured cost is currently zero, which is a fact this ticket did not have.
