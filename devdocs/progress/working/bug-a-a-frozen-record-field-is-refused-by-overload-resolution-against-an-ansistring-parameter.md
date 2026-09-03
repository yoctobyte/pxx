---
type: bug
track: A
prio: 90
status: working
summary: Under -dPXX_SHORTSTRING, passing a frozen record FIELD to an AnsiString
  parameter is refused by overload resolution on ALL SEVEN targets; a plain
  variable of the same type is accepted, and both compile in the default mode.
owner: frankB
---

# A frozen record field is refused by overload resolution against an AnsiString parameter

**Phase-4 blocker on every target — the first one that is not target-specific,
and the first that touches wasm32 and xtensa at all.**

```pascal
program ov;
type R = record f: string[10]; end;
procedure Show(const a: AnsiString); begin WriteLn('[', a, ']'); end;
var r: R; s: string[10];
begin r.f := 'field'; s := 'plain'; Show(s); Show(r.f); end.
```

```
error: no overload of Show matches these arguments
  argument types: (ShortString)
    Show(AnsiString)
  near: Show ( r . f ) >>> ; end .
```

Measured at `4a84ba4b5`, compiler sha `e102360f2c11`:

| target | default | `-dPXX_SHORTSTRING` |
| --- | --- | --- |
| x86-64, i386, arm32, aarch64, riscv32, wasm32, xtensa | compiles, `[plain]` `[field]` | **refused, all seven** |

**`Show(s)` on a plain variable is ACCEPTED in the same program; only the FIELD
is refused.** A bare variable normalises to `tyString` via `StrValTk` while a
field load keeps `tyShortString`, so the field is the operand that reaches
overload resolution with the narrow kind.

`TypesCompatible` in `symtab.inc` carries the frozen-param ← managed-arg rule
and not the reverse.

## Why this one is different from the rest of the family

Every other byte-prefix defect found so far is a wrong VALUE or a crash on one
or two targets. **This is a compile-time refusal on all seven**, so it cannot be
missed at runtime and cannot be hidden by a guard — but it also means the flip
cannot land anywhere until it is fixed. Ranked above the concat and `Copy`/`Pos`
crashes for that reason.

**It is an honest refusal, not a miscompile** — the compiler declines rather
than emitting something wrong, which is the right failure.

## Provenance

Found by franka-29 while building the regression battery for the i386 fixes
(`21544412b`), reported to the coordinator rather than taken silently.
Independently reproduced and extended from five targets to all seven here,
including wasm32 and xtensa (xtensa needs `--platform=posix
--xtensa-soft-mulhigh`; bare `--target=xtensa` is the ESP profile and refuses
for unrelated reasons).

## HELD, NOT UNSTARTED — the fix is written and DELIBERATELY not landed (frankB, 2026-09-03)

**Ordering agreed with franka-29, which is on
`bug-a-a-frozen-string-argument-is-empty-through-a-constructor-or-a-virtual-call-on-every-cross-backend`
(prio 92). It lands first; this follows.** The reason is measured, not
prudential:

**This fix ADMITS a shape whose conversion is already broken, so landing it
first replaces an honest compile-time refusal with a silent wrong value.**

```pascal
type TArr = array[0..2] of string[10];
procedure ShowA(const q: AnsiString);
a[1] := 'elem';  ShowA(a[1]);
```

Refused today. With this fix it compiles, and in the
`-uPXX_MANAGED_STRING -dPXX_SHORTSTRING` corner it prints sixteen NULs, then a
WIDE length word of 4, then `elem` — the handle points 22 bytes before the
string's real prefix. `WriteLn(a[1])`, `m := a[1]` and a frozen `string[10]`
parameter are all correct in the same program and the same corner; only the
frozen→managed ARGUMENT conversion is wrong, and that is the ~15-copy ladder
franka-29 is unifying into `IRLowerCallArg`.

**The ranking fact worth keeping: when a refusal is the only guard over an
untested path, fix the path first.** This ticket's own body praises the
refusal for being honest; that is exactly why fixing it out of order is worse
than leaving it.

## The fix, so it is recoverable from origin if this tree is lost

Two hunks, neither in `IRLowerCallArg` nor in `TypesCompatible`'s callers.

1. `compiler/symtab.inc`, at the top of `TypesCompatible`:

```pascal
  if TypeIsFrozenString(aType) then
    aType := IntToTypeKind(StrValTk(aType));
```

Every string rule in that function names `tyString` and there are three frozen
kinds. Asked ONCE on the ARGUMENT side rather than at each rule; the
PARAMETER's frozen kind still selects its own rule, so a frozen formal keeps
its exact-match rank.

**Normalised there and NOT at the field node**: the field's own tag is
load-bearing — `IRFrozenKindOfAddr` has no symbol to walk back to for an
`IR_FIELD` and falls through to the node's own kind for the prefix width, so
retagging the field the way `pasparser_expr.inc` retags concat operands would
fix overload resolution and break every width below it. (That is not
hypothetical: it is exactly the mechanism of
`bug-a-a-frozen-record-field-as-a-concat-operand-segfaults`, found and fixed
the same day.) `TypesCompatible` asks about VALUE compatibility, where the
width is not the question.

2. `compiler/pasparser_call.inc`, `OverloadArgRank`'s string-flavour arm:
`TypeIsFrozenString(aTk)` in place of `aTk = tyString`. The field was sinking
to rank 2 (merely compatible) where the identical variable got rank 1
(preferred conversion) — a ranking asymmetry between two spellings of one
type, which is how `P(r.f)` and `P(s)` bind to different overloads. Parameter
side unchanged.

## Verified before holding

`test/test_frozen_arg_overload.pas` (written, NOT yet wired) covers plain
variable, record field, field-of-field, array element with a CONSTANT index,
array element with a VARIABLE index, a function RESULT typed `string[10]`, and
a two-candidate `ShowI(Integer)` / `ShowI(AnsiString)` pick with an Integer
control row. **No literal is ever the argument** — franka-29 measured that a
string literal is correct through every route on every target, so a suite built
from literals passes with the bug fully present.

All seven targets: x86-64, i386, arm32, aarch64 and riscv32 run
byte-identical in both byte-prefix modes; wasm32 and xtensa compile (the
symptom was a compile refusal, so compiling IS the assertion there). xtensa
needs `--platform=posix --xtensa-soft-mulhigh`.

**Re-measure the `-u -d` array-element corner before landing.**
