---
slug: bug-p-a-user-type-whose-name-shadows-a-builtin-is-unusable
track: P
type: bug
prio: 45
status: backlog
found: 2026-08-31
found-by: frank-rust
owner: unassigned
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
