---
type: bug
track: A
prio: 90
status: done
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

## WIDER THAN THE FLAG: a frozen FUNCTION RESULT is refused in the DEFAULT mode, at the pin

Found while writing the acceptance rows, and it changes this ticket's scope.

```pascal
program fr;
function Mk: string[10]; begin Mk := 'ret'; end;
procedure Show(const a: AnsiString); begin WriteLn('A[', a, ']'); end;
var s: string[10];
begin s := 'plain'; Show(s); Show(Mk); end.
```

```
error: no overload of Show matches these arguments
  argument types: (string[N])
```

**No flag. Default mode. Identical under `stable_linux_amd64/default/pinned`**
(`1eec4dc5e0a7`), so this ships today in every `$(PXX_STABLE)` build. The
table at the top of this ticket says the default mode compiles on all seven
targets — that is true for a record FIELD and false for a function RESULT,
because the two arrive narrow by different routes: a field carries
`ASTTk`, a call node carries `Procs[].RetType`, the STORAGE kind, and only the
latter is narrow in the default build (tyFixedString) as well as under the
flag (tyShortString).

So this is not only a phase-4 blocker. The same normalisation fixes a
default-mode refusal that is live at the pin.

## The held test program, so a restart cannot take it

Written as `test/test_frozen_arg_overload.pas`. **It IS tracked as of
`bab799137` and it is NOT wired into any build rule** — deliberately, because
three of its four modes need this fix to compile at all. `gate.sh quick`'s
"this push wires the tests it adds" is green (it reads the push's own diff),
and it does not belong in `test/UNWIRED.txt`, which is for files whose end
state is "nothing runs it". Wire it in the commit that lands the fix. The
source is duplicated below so the rows survive even if the file does not.
The header comment on the real file explains why each row fails differently;
the rows themselves are the part that must survive.

```pascal
type
  Inner = record g: string[10]; end;
  R = record f: string[10]; n: Inner; end;
  TArr = array[0..2] of string[10];

procedure Show(const a: AnsiString);
begin WriteLn('A[', a, ']'); end;

procedure ShowI(const a: Integer);
begin WriteLn('I[', a, ']'); end;

procedure ShowI(const a: AnsiString);
begin WriteLn('AI[', a, ']'); end;

function Mk: string[10];
begin Mk := 'ret'; end;

var
  r: R; a: TArr; s: string[10]; i: Integer;
begin
  r.f := 'field'; r.n.g := 'nested'; a[1] := 'elem'; s := 'plain'; i := 1;
  Write('plain   '); Show(s);
  Write('field   '); Show(r.f);
  Write('nested  '); Show(r.n.g);
  Write('elem    '); Show(a[1]);
  Write('elemvar '); Show(a[i]);
  Write('ret     '); Show(Mk);
  Write('pick    '); ShowI(r.f);
  Write('int     '); ShowI(7);
end.
```

Expected output, measured identical in the default, `-dPXX_SHORTSTRING` and
`-uPXX_MANAGED_STRING` modes with the fix applied:

```
plain   A[plain]
field   A[field]
nested  A[nested]
elem    A[elem]
elemvar A[elem]
ret     A[ret]
pick    AI[field]
int     I[7]
```

**The fourth mode, `-uPXX_MANAGED_STRING -dPXX_SHORTSTRING`, gives `elem` and
`elemvar` as garbage** — that is the frozen→managed argument conversion, not
this fix, and it is the reason this is held. Wire the first three modes when
this lands and add the fourth once the conversion is unified.

**A CAUTION PAID FOR TWICE TODAY**: the first version of this section pasted an
"expected output" read off a STALE binary at a scratch path — the compile had
failed, the previous run's executable was still there, and `&&` on the compile
was missing, so a confident-looking eight-row block went in that was the
`-u -d` corner's garbage. Same failure as the handover's rule 2. Branch on the
compile, and use a fresh output path.

## LANDED — and the array element needed a THIRD arm nobody had written

franka-29's conversion unification (`5e7c7eab2`) went in first, as agreed. On
top of it the widening is two hunks, and re-measuring the held corner found a
third defect that only became reachable once the refusal lifted.

**`-uPXX_MANAGED_STRING` MAKES `AnsiString` ITSELF FROZEN**, so in the `-u/-d`
corner `Show(const a: AnsiString)` has a tyString formal and a `string[10]`
argument is a WIDTH MISMATCH between two frozen kinds, not a frozen→managed
conversion at all. That copy is decided by `ASTFrozenArgTk`, and it had ONE
arm — `AN_IDENT`. The IR said it plainly:

```
-d only            -u -d
store_sym tk=23    (nothing)
load_sym  tk=23    index tk=25
arg       tk=23    arg   tk=4      <- the raw element address, tagged tyString
```

A variable and a field each got a temp; an array element did not, because
`ASTTk` for `a[i]` is the generic tyString, that EQUALS the frozen formal, no
mismatch was seen and no copy was emitted — a 1-byte-prefixed element handed
to a callee reading an 8-byte prefix. `ASTFrozenArgTk` now has three arms, one
per ENTITY that records the width: the symbol, `RecFieldType`, and the array
symbol's own `TypeKind`. The field arm is added even though `ASTTk` happens to
be right for a field today — that is luck, and
`bug-a-a-frozen-record-field-as-a-concat-operand-segfaults` is the same tag
being flattened one node type over.

**Three entities, three routes, and the sibling nobody wrote is the one that
stays broken** — the fourth instance of that shape in this family today.

## Verification

- `test/test_frozen_arg_overload.pas` wired FOUR ways; `test_shortstring_concat`
  still green in its four.
- **Positive control: with all three compiler hunks reverted (compiler
  `6ef083d371d8`, franka-29's tip) every one of the three test files is
  REFUSED AT COMPILE TIME in every mode, the default included** — the function
  result row is what makes even the no-flag rows fail without this. No row can
  pass for another reason.
- Five runnable targets × both modes × two programs: byte-identical output,
  20 cells. wasm32 and xtensa compile in both modes.
- **Leak-checked, because a value row cannot see ownership**: each of the four
  argument spellings materialises its own hidden owning temp, so a
  variable-only loop proved ownership for one of four. `test_frozen_arg_no_leak`
  extended to all four; `allocs=10975 frees=10970 live=5` against a bound of
  200. The allocation count rising from ~3000 to ~11000 is also the evidence
  that the new loops actually reach the path rather than passing vacuously.
- `tools/gate.sh quick` GREEN with the FPC seed canary run, not skipped.

## Left standing, deliberately

The ~15 inline backend conversion arms franka-29 left in place. They are
believed unreachable for anything funnelling through `IRLowerCallArg` and
believed-dead is not proven-dead; deleting them wants a per-backend canary.
Nothing here assumes they are dead.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
