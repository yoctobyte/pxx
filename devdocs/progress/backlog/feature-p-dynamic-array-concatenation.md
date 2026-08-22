---
track: P
prio: 40
type: feature
blocked-by: []
status: backlog
summary: "`Concat(a, b)` and `a + b` over dynamic arrays are refused with `arithmetic operator not supported for dynamic arrays`. FPC supports both — Concat in objfpc mode, `+` under {$modeswitch arrayoperators} and in Delphi mode. The diagnostic is honest (it replaced a silent wild-pointer miscompile), but the feature is ordinary and the machinery for it already exists."
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
