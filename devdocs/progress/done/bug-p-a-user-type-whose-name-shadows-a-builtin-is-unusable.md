---
slug: bug-p-a-user-type-whose-name-shadows-a-builtin-is-unusable
track: P
type: bug
prio: 45
status: done
found: 2026-08-31
found-by: frank-rust
owner: frankC
blocked-by: []
summary: "SELF-INCONSISTENT, no oracle needed: with `type Currency = record a,b,c: Integer end`, `SizeOf(Currency)` answers 12 in an expression and 8 inside an array bound in the SAME program (`12 8 8`; fpc `12 12 12`) — ParseTypeKind still consults the builtin type name before the user's own type tables, so such a type is also unusable as a variable's type (`v.a := 1` gives 'a value of this type has no members'). Declaration-side twin of the SizeOf precedence bug fixed in 582e4de09; that fix covered SizeOf only. Because it is self-inconsistency rather than an FPC disagreement, it cannot be ranked as a compat item."
---

# A user type whose name shadows a builtin is unusable as a variable's type

## The sharpest repro is self-inconsistency, not a disagreement with FPC

Found by frankwasm, re-measured by frank-rust on a fresh HEAD build
`a673fa2206c4` (HEAD `26b5a5d066ed`, 2026-08-31):

```pascal
program SelfInc;
type Currency = record a, b, c: Integer; end;
     TA = array[0..SizeOf(Currency) - 1] of Byte;
var x: TA;
begin
  Writeln(SizeOf(Currency), ' ', SizeOf(x), ' ', Length(x));
end.
```

```
pxx : 12 8 8        fpc 3.2.2 : 12 12 12
```

**The same expression text answers 12 and 8 in the same program, ten lines
apart** — 12 through the SizeOf path fixed in `582e4de09`, 8 through
`ParseTypeKind` in the array bound, which still consults the builtin name first.

Prefer this over the pxx-vs-FPC form as the ticket's headline repro, for two
reasons. It needs **no oracle** to be obviously wrong, so nobody has to agree
about what our `Currency` ought to be first. And self-inconsistency is the one
form that **cannot be ranked as a compat item** under the compat ceiling — it is
not "FPC accepts a form we reject", it is us giving two answers to one question.


## Repro

```pascal
program shadowvar;
type Currency = record a, b, c: Integer; end;
var v: Currency;
begin
  v.a := 1; v.b := 2; v.c := 3;
  WriteLn(SizeOf(Currency), ' ', SizeOf(v), ' ', v.a, v.b, v.c);
end.
```

```
pxx:  pascal26:5: error: a value of this type has no members
                         (only records, classes, interfaces and variants do)
FPC:  12 12 123
```

The type declaration itself is accepted; it is the **use as a variable's type**
that silently resolves to the builtin, so `v` is an 8-byte `Double` slot with no
members. Reproduces on the pinned compiler too — pre-existing, not a regression.

Any builtin name the declaration path knows will do: `Currency`, `Comp`,
`TDateTime`, `ValReal`, `LongBool`. `SizeOf(Currency)` answers **12** correctly
as of the precedence fix below, so the compiler now disagrees with *itself* — it
sizes the user's record and declares the builtin.

## Why it is the twin of the SizeOf bug, and where to fix it

[[bug-p-sizeof-rejects-twelve-type-names-that-a-declaration-accepts]] was the
same precedence error in `SizeOf`: `BuiltinTypeNameTk` was consulted before the
record/alias/array/enum/variable tables, so a builtin stole the name from a user
declaration. That is fixed — the builtin is now demoted when a user declaration
claims the name, and restored as a fallback when the user lookup resolves to
nothing.

`ParseTypeKind` has the same ordering and has not been fixed. The fix should
follow the same shape rather than a second mechanism
(`devdocs/dev/normalise-dont-special-case.md`), and it should keep the same
fallback: several builtin names ALSO match an internal registration, and
`shortstring` is deliberately excluded from the shared table because it sets
`LastTypeStrCap` and is not side-effect-free.

## Ranked at 45, below its twin, deliberately

This one **fails loudly at compile time**. Its twin produced wrong *sizes* —
`SizeOf(Currency)` 12 → 8, a `Boolean` named `longbool` 1 → 4 — feeding `GetMem`
and `Move` with no diagnostic at all. A program that hits this bug does not
build; a program that hit the other one shipped.

Real code that would hit it is also narrower: shadowing `Currency` or
`TDateTime` with your own record is legal Pascal and FPC accepts it, but it is
not common. Rank it by how much real code redeclares a builtin name, not by how
surprising the error message is.

## Guard when it is fixed

`test/test_sizeof_user_name_shadows_builtin.pas` already covers the SizeOf half
and is byte-identical to FPC 3.2.2. Extend it (or add a sibling) with the
declaration half — *use* the shadowing type, do not merely size it — and keep
its control rows: builtin names that nothing in the file shadows, which is what
catches a fix that stops consulting the builtin table altogether. Note that
asserting `SizeOf(LongBool) = 4` is NOT a control in a file that declares a
variable called `longbool` — that name means the variable, and FPC agrees.

## A SECOND symptom, and it is why this outranks a "you cannot declare it" bug

`SizeOf` has **two** implementations. The expression one (`ParseFactor`) has the
precedence fix. The **constant-expression** one (`pasparser_expr.inc:10477`,
`feature-sizeof-const-intrinsic-in-const-eval`) resolves its operand by calling
**`ParseTypeKind`** — so it inherits this bug verbatim:

```pascal
type Currency = record a, b, c: Integer; end;
     TA = array[0..SizeOf(Currency) - 1] of Byte;   { pxx: 8   FPC: 12 }
```

The array silently gets **8 elements instead of 12**. No diagnostic. So this
ticket is not only "the type is unusable" — through the const path it also
produces the same class of silent wrong size its twin did, in array bounds and
default parameter values.

**Fixing `ParseTypeKind` fixes both symptoms and both call sites**, which is the
argument for doing it there rather than patching the const-eval arm.

## The other half of the fix: WHEN you are entitled to ask

Ordering alone is not sufficient, and this is measured elsewhere rather than
guessed. frankwasm hit the same family at `19bb32f31` with the ordering ALREADY
correct — `FindUClass` ran first and it still refused a legal program, because
the user's declaration **had not been parsed yet** when the check ran. Fixed at
`d9e3420e5` by deferring the check to type-section close.

So the rule for this family is two-part: **a name must be settled against the
program, not against the builtin table, and asked at a point where the program
is complete enough to answer.** Asking at the wrong moment gives a correct
lookup over an incomplete world.

`SizeOf`'s expression path is not exposed to the second half — by the time a
statement is parsed the type sections are closed, and the one ordering that
looks wrong (`SizeOf(Currency)` textually *before* `Currency` is declared) is
answered 8 by FPC too, because the name genuinely is not declared yet there.
**Measured both directions rather than assumed**; whoever fixes `ParseTypeKind`
should re-ask that question for the declaration path, where forward references
inside one type section are ordinary.

## Fixed 2026-09-02

`ParseTypeKind` already had the guard and it was one table too narrow:

```pascal
tnHasAlias := FindTypeAlias(lo) >= 0;
```

Its own comment said "a source/RTL alias of this name beats every builtin
name", and every builtin arm in the chain is guarded with `not tnHasAlias`. So
an ALIAS beat a builtin and a RECORD did not. The SizeOf site fixed in
`582e4de09` consults six tables for the same question. **Same predicate, two
places, one narrow** — the umbrella's second shape (duplicated tables that
disagree), not a second arm, so the fix is the seam and not a special case.

Now `FindTypeAlias or IsRecordType or FindUClass or IsClassType or
FindArrayType or FindEnumType`, and renamed `tnUserDecl`, because "HasAlias"
was an 80%-accurate name for what it now tests and those are worse than
0%-accurate ones. It asks the TYPE tables only: SizeOf legitimately also checks
`FindVarSym`, but a variable named `Currency` does not make `Currency` a type
in a type position.

The guarded-branch shape is unchanged, so this can still only ever make a
declaration WIN, never the reverse.

## Verified

Extended `test/test_sizeof_user_name_shadows_builtin.pas` — the sibling test
from `582e4de09` — rather than adding a second file, since it is the same
question. Its own comment recorded row j as deliberately NOT asserted because
`SizeOf(v)` on a user record variable answered 8 before and after that fix;
that is this defect, so the row is now asserted and the comment updated.

New rows: `SizeOf(cv)` = 12, member access `cv.a + cv.b + cv.c` = 6 (a hard
compile error before), the const-eval path `array[0..SizeOf(Currency)-1]` = 12
(the `12 8 8` self-inconsistency), and the shadowing ARRAY type = 10. Plus the
control that goes missing: an UNSHADOWED builtin must still resolve as a
variable's type — `WideChar` (2) and `ByteBool` (1), chosen because no fallback
here produces 2 or 1.

**No expected value under test is 4 or 8.** 12, 10, 6, 2, 1 — none is a number
a fallback returns, so no row can pass by the machinery doing nothing.

- pxx output is byte-identical to FPC 3.2.2 `-Mobjfpc -Sh` across all 14 rows.
- Positive control: the **pinned** compiler REFUSES TO BUILD the test —
  `error: a value of this type has no members`, a build-time rejection rather
  than a wrong value.
- `gate.sh quick` GREEN, FPC seed canary PASS.

**Blast radius measured rather than assumed.** The change can only affect a
program that declares a type whose name collides with a builtin. Across
`lib/rtl` and `lib/pcl` (265 declared type names) there is exactly ONE such
name: `Text`, declared as a record in `lib/rtl/textfile.pas` and as a class in
`lib/pcl/tkinter.pas`. A `Text`/`TextFile` round-trip compiles to byte-identical
code/data/bss before and after. That is why the quick tier is proportionate here
and the gate was not widened.

Worth recording: the first version of that collision measurement was a
`comm` whose builtin-name list had several names per line, so it compared whole
lines and could never match. It reported zero collisions — the right-looking
answer — and only an injected must-be-reported name exposed it. The real answer
was one collision, not zero.

## FPC's default mode is not a disagreement

`fpc selfinc.pas` with no mode switch prints `6 6 6` where pxx prints
`12 12 12`, which looks like a fresh divergence and is not: mode `fpc` has
`Integer` = 2 bytes (measured: `SizeOf(Integer)` is 2 there, 4 under
`-Mobjfpc`). Under `-Mobjfpc`/`-Mdelphi` FPC prints `12 12 12`, matching. The
ticket's recorded `fpc 3.2.2 : 12 12 12` is right; it was measured in a
comparable mode.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 2ba37ba91.
