---
track: P
prio: 40
type: feature
blocked-by: []
status: done
summary: "`Concat(a, b)` and `a + b` over dynamic arrays are refused with `arithmetic operator not supported for dynamic arrays`. FPC supports both — Concat in objfpc mode, `+` under {$modeswitch arrayoperators} and in Delphi mode. The diagnostic is honest (it replaced a silent wild-pointer miscompile), but the feature is ordinary and the machinery for it already exists."
owner: claude-A
---

# Dynamic-array concatenation

Found 2026-08-22 by an FPC differential sweep over language shapes
(`fpc -Mobjfpc -O1` 3.2.2 vs pxx `3a107f008`).

## Repro

```pascal
{$mode objfpc}{$H+}
var a, b, c: array of Integer;
begin
  SetLength(a, 2); a[0] := 1; a[1] := 2;
  SetLength(b, 1); b[0] := 3;
  c := Concat(a, b);                { fpc: 3 1 3 }
  Writeln(Length(c), ' ', c[0], ' ', c[2]);
end.
```

```
pascal26: error: arithmetic operator not supported for dynamic arrays
          (`a + b` array concatenation is not implemented)
```

Both spellings fail, including `a + b` under `{$modeswitch arrayoperators}`,
and `Concat` over an `array of string` as well as `array of Integer`.

## Why this is not a bug

The diagnostic is deliberate (`ir.inc` ~8423): it replaced a silent miscompile
where `a + b` fell through to the integer/pointer IR_BINOP, ADDED the two array
HANDLES and produced a wild pointer — `bug-dynarray-concat-silent-miscompile`.
Refusing honestly was the right first move; implementing the operation is the
second.

## Shape of the fix

The pieces exist: `AN_DYN_COPY` builds a fresh dyn array and copies a range
into it (`feature-copy-intrinsic`), and `Insert`/`Delete` over a dyn array
already resize and shift (`feature-dynarray-insert-delete`). Concat is
SetLength(dest, la + lb) followed by two element-wise copies, with the same
managed-element ARC the existing paths use — so route both spellings to one
lowering rather than growing two.

Both spellings must reach it: `Concat(a, b, ...)` (n-ary, as the string
intrinsic already is) and the `+` operator. Follow
`normalise-dont-special-case.md` — one lowering, two entry points — or the
second entry point is the one that stays broken.

Cases the test must cover: an empty operand on either side, both empty, a
managed element type (`array of string`, refcounts balanced), `a := a + b`
(the destination aliasing an operand), and three-way `Concat(a, b, c)`.

## Gate

`make compiler/pascal26` + a test asserting fpc parity on all of the above +
`tools/gate.sh quick`.

## Resolution (2026-08-25)

Both spellings implemented, through ONE construction — `MakeDynConcat`
(`pasparser_expr.inc`, next to `MakeWholeDynCopy`), called from the `Concat`
intrinsic arm and from `ParseSimpleExpr`'s `+` arm.

**Concat IS the array-splice Insert with the index pinned past the end.**
`PXXDynInsArrFill` already clamps its index to `[0..len]`, so a MaxInt index
means "append", and `AN_DYN_INSERT`'s whole apparatus — fresh temp,
`SetLength(temp, 0)` then the sizing SetLength, the raw fill,
`PXXDynArrayRetainImmediate` for managed and nested element types, the
prologue nil-init — serves unchanged. No second lowering was written, and no
second ARC story exists to drift. That is the ticket's own "one lowering, two
entry points", taken literally.

The index is a CONSTANT rather than a `Length(a)` node deliberately: a Length
node would re-evaluate the left operand, so `Concat(F(), G())` would call F
twice. `MakeWholeDynCopy` pins its count the same way for the same reason.

Shape readers taught that the node IS an array: `AN_DYN_INSERT` joins
`AN_DYN_COPY` in `NodeDynDepth` / `NodeDynBaseTk` / `NodeDynBaseRec`
(`ast_arena.inc`) and in the twin `DynArrayNodeDepth` (`symtab.inc`) — edited
together, as that function's own note demands. Without those arms a concat
stops being an array the moment it is used as an operand, which is what makes
`Concat(a, b) + b` and `Length(Concat(a, b))` work.

**Refusals kept honest.** `-`, `*`, `div`, and a `+` with an array on only one
side still hit the `ir.inc` diagnostic (text updated — it no longer claims
concatenation is unimplemented). Mismatched element type or nesting is refused
in `MakeDynConcat` with a specific message rather than silently striding wrong;
frozen-string elements are refused exactly as dynamic-array Insert refuses them.

## Verification

`test/test_dynamic_array_concatenation.pas` (wired into `test-core`), 15 rows,
`.expected` is fpc 3.2.2's own output — matched byte for byte on the first run.
Covers every case the ticket named: empty on either side, both empty, three-way
`Concat(a, b, c)`, `a := a + b` and `a := b + a` (destination aliases an
operand), `u := u + u` (BOTH operands alias it), `array of string` (managed),
`array of array of Integer` (nested handles), a call result as an operand, a
concat nested inside a concat, and `Length(Concat(a, b))`.

Refcount balance measured, not argued: 200,000 iterations of managed +
nested concat peak at **392 KB RSS** — flat, and no double free.

`make compiler/pascal26` converged in one round; `tools/gate.sh quick` GREEN.

## Log
- 2026-08-25 — resolved, commit f2bad72e9.
