---
slug: bug-p-a-nested-specialization-is-named-by-its-alias-so-one-name-serves-every-outer-specialization
title: "A specialization is minted under its ALIAS name rather than its canonical key -- two aliases of one specialization are two classes, so `a is TOtherAlias` is FALSE where fpc says TRUE"
track: P
prio: 55
type: bug
blocked-by: []
status: working
owner: frankS
created: 2026-09-06
summary: "TOP-LEVEL HALF FIXED 2026-09-08 at cd2d264c72df; the NESTED half, which is this ticket's title, is OPEN. Fixed: two aliases of ONE specialization (`TIntBox` and `TIntBox2`, both `= specialize TBox<Integer>`) were two classes, so `a1 is TIntBox2` answered FALSE where fpc says TRUE and `a1 as TIntBox2` was a hard Runtime error 219 -- while `a2 := a1` was accepted by BOTH compilers, which is the combination that hid it. NOT fixed by routing the mint through the canonical key (this ticket's own proposal, which renames every alias-bound specialization in fgl and rtl-generics and stays parked for that): when an EQUIVALENT specialization is already declared and visible, the new name is registered as a UCLASS ALIAS of that class and nothing is minted. Deliberately not a second Specializations[] row -- BufferGenericMethod walks that table once per matching row and would re-create the duplicate-method warning this ticket opens with. Equivalence is d98d297de's: same template BY INDEX, same arity, same argument spellings AND same SpecArgIdentity, asked only of rows this scope can see. ClassName measured all three ways -- fpc prints `TBox<System.LongInt>` for both aliases, pin v407 printed `TIntBox`/`TIntBox2` (the defect), pxx now prints `TIntBox` for both: fpc's SHAPE, not fpc's spelling, and the first alias's name is unchanged, which the canonical-key rename would not have managed. STILL OPEN, re-measured at cd2d264c72df and not assumed: `TEnumSpec = specialize TEnum<T>` inside a generic class is still minted under the ALIAS, so `specialize TList7<Integer>` and `specialize TList7<String>` still mint two classes called TEnumSpec and tnest8 still stops at `incompatible types: cannot assign Integer to AnsiString`. The two outer specializations pass DIFFERENT arguments, so the collapse never applies there -- that half genuinely needs the canonical key, which CollectHoistCandidates already computes (`TI$TEnumSpec`, `TS$TEnumSpec`) behind the two gates recorded below. tgeneric16.pp's one divergent line is that half and its skip row stays."
---

# The shape

```pascal
unit unest7; {$mode objfpc}
interface
type
  generic TEnum<T> = class(TObject)
    V: T;
    function GetCurrent: T;
  end;
  generic TList7<T> = class(TObject)
  type
    TEnumSpec = specialize TEnum<T>;     { <- named by the ALIAS }
  public
    function Mk: TEnumSpec;
  end;
implementation
function TEnum.GetCurrent: T; begin Result := V; end;
function TList7.Mk: TEnumSpec; begin Result := TEnumSpec.Create; Result.V := 9; end;
end.
```

```pascal
program tnest8; {$mode objfpc}
uses unest7;
type
  TI = specialize TList7<Integer>;
  TS = specialize TList7<String>;    { DIFFERENT type argument -- second mint }
var a: TI; b: TS;
begin a := TI.Create; b := TS.Create; WriteLn(a.Mk.GetCurrent); end.
```

```
pascal26:0:  error: incompatible types: cannot assign Integer to AnsiString
pascal26:15: warning: duplicate definition of 'TEnumSpec.GetCurrent' with the same
             parameter types; the later body wins, but calls written between the two
             bind to the earlier one
```

**Legal code is refused.** One instantiation alone compiles and runs; adding a
second with a different type argument breaks the first.

# MECHANISM — CORRECTED 2026-09-06 (frankS), the section below it was WRONG

**I wrote the section below from reading and it names the wrong routine.**
`ScanRangeForNestedSpecs` is not on this path at all. Measured at
`c41acdb80137` with two temporary probes, and the mint trace settles it in one
line: `PXXDBG=p.mint:*` on the repro prints **nothing**. Nothing is minted
through `EmitSpecDecl` here, so no guard of its can be the cause.

What actually happens, from a probe on the hoist registration and on the class
stream:

```
PROBE hoistcand  nm=TEnumSpec full=TI$TEnumSpec
PROBE streamclass spec=TI         hoistCount=1
PROBE streamclass spec=TEnumSpec  hoistCount=0     <- the mint, under the ALIAS
PROBE hoistcand  nm=TEnumSpec full=TS$TEnumSpec
PROBE streamclass spec=TS         hoistCount=1
PROBE streamclass spec=TEnumSpec  hoistCount=0     <- again, same name
```

**The machinery to fix this already exists, is already correct, and is never
reached.** `CollectHoistCandidates` registers `TEnumSpec` once per outer
specialization with a name that ALREADY carries the distinction —
`TI$TEnumSpec` and `TS$TEnumSpec`. The names are right. Nothing asks for them.

Two gates stand between the candidate and the rename, and each is enough on its
own:

1. **`HoistUsed` is reachable from exactly one place** — `HoistedNameFor`, called
   only from `NestedSpecArg`, i.e. when the nested name appears as a type
   ARGUMENT of another specialization. A nested type used as a RETURN type (this
   repro), a field type or a variable type never marks itself used.
2. **`EmitHoistedDecls` is called from exactly one place** — inside the
   DEFERRAL arm of `ParseSpecialization`, behind `if hoistPending`. A
   specialization that does not defer never emits a hoisted declaration however
   used its candidates are.

So `TEnumSpec = specialize TEnum<T>` inside the outer body is streamed with
`T` substituted and its LHS untouched, and `ParseSpecialization` mints the class
under the alias as written — once per outer specialization, same name both times.

**Hoisting is scoped to the deferral path.** It was built for the case where a
nested type is NAMED AS A GENERIC ARGUMENT and therefore has to exist at top
level before the specialization that mentions it can be emitted. This ticket is
the same naming problem arriving through a path that has no reason to defer.

# What a fix has to do, now that the path is known

Not "mint under a different name" alone — that was measured to be insufficient.
The rename has to be applied CONSISTENTLY to three things, and the third is why
this is not a small edit:

1. the alias declaration's own LHS, so the class is minted as `TI$TEnumSpec`;
2. every reference in the CLASS BODY, which streams with `HoistActive` true;
3. every reference in the METHOD BODIES, which stream **separately and with
   `HoistActive` false** — the comment at the one `HoistActive := True` site says
   method bodies deliberately need no collapse because "they refer to the nested
   type by NAME, and the name is still declared in the class, now as an alias".
   That reasoning holds only while the in-class alias survives, so renaming the
   LHS invalidates it.

Keeping the in-class alias (`TEnumSpec = TI$TEnumSpec`) preserves (3) and is what
the existing hoist design does — which means the real fix is to reach the
existing machinery from the ordinary path, not to write new naming.

**Blast radius is why I parked it rather than pushing on.** Both gates are load-
bearing for the case hoisting was built for, and lifting either changes the
naming of every nested type in every generic class — fgl and rtl-generics
included, both corpus rungs. That wants a full tier, not a quick one.

# ORIGINAL MECHANISM SECTION — SUPERSEDED, kept because the reasoning about KEYS still holds



`ScanRangeForNestedSpecs` registers the prerequisite under
`aliasNm := NestedSpecAlias(...)` — the alias as written — and both guards are
name-only:

```pascal
if (not CaseEqual(aliasNm, specName)) and (not NestedSpecKnown(aliasNm)) then
  for k := 0 to NSpecCount - 1 do
    if CaseEqual(NSpecName[k], aliasNm) then dup := True;
```

```pascal
function NestedSpecKnown(const nm: AnsiString): Boolean;
begin Result := (FindSpecialization(nm) >= 0) or (FindUClass(nm) >= 0); end;
```

So the name `TEnumSpec` identifies the nested specialization **globally**, with
nothing in it derived from the argument the outer class was specialized on. The
outer template's body is streamed once per outer specialization and each pass
mints a member set under that one name.

This is the same collision-with-a-legal-value trap the alias table's own
`AliasOwnerCi` comment describes, and the same one `SPEC_HOST_NONE = -2` was
chosen to avoid: **a key that cannot distinguish the things it is used to look
up.** Here the key is a name and the thing it must distinguish is the type
argument.

# Severity depends on the arguments, which is why it reads as harmless

| corpus | result |
| --- | --- |
| real `fgl.pp`, `TFPGList<Integer>` + `TFPGList<String>` in one program | 3 warnings (`TFPGListEnumeratorSpec` `.GetCurrent`/`.Create`/`.MoveNext`), **compiles, runs, correct output** |
| the reduction above | **compile error**, legal program refused |

fgl survives because the merged bodies happen to stay type-compatible there. That
is luck, not a property — and it is exactly the shape that makes this look like a
cosmetic warning. `for i in list` over the wrong enumerator body is a silent
wrong answer waiting for the right pair of type arguments.

# Not caused by recent work

pin v404 prints the same warnings on the same fgl program. Found while looking at
a warning frankA saw on an unrelated reduction.

# What to measure first

Whether the fix is a NAME (mint `TEnumSpec$Integer` and add
`TEnumSpec -> TEnumSpec$Integer` to the substitution set in force while that
outer specialization's body is streamed) or a SCOPE (register the nested type
against the specialized owner, as `AddNestedType(ownerCi, ...)` already does for
in-body nested types, and resolve it through the owner rather than globally).
The name route is smaller and matches how `SpecializeStreamAt` already renames;
the scope route is the one that stops the global namespace growing a row per
nested type per instantiation.

Either way the guard has to be keyed on `(alias, argument list)` — the pair the
diagnostic already proves is not currently distinguished.

## A warning for whoever reduces this further

The reduction in this ticket fails at COMPILE time, which is the easy case. The
`fgl` arm does not — it compiles, runs, and prints the right answer with the
duplicate warning showing. **So any smaller reduction that runs rather than
refusing has to be built to discriminate, and two ordinary choices both hide
it:**

- **Do not assert the FIRST field of the inner class.** Offset 0 is what a lost
  or wrongly-bound base resolves to, so the first member is the one that cannot
  tell a correct read from a broken one. Give the inner class at least two
  fields and read the SECOND. (frank-optimize's rule, banked `5b93e5046`; it is
  the same shape as the "expected value collides with the default" rule this
  file already carries.)
- **Do not specialize the outer on two type arguments of the same width.**
  `<Integer>` and `<LongInt>` merge into a body that is wrong and harmless.
  The pair has to differ in a way the merged body cannot survive — which is why
  `<Integer>` against `<String>` is the pair in the reduction above, and why
  fgl's own `TFPGList<Integer>` + `TFPGList<String>` still runs correctly: the
  two enumerator bodies it merges happen to stay compatible.

Both are the same question asked of a reduction rather than of a guard: **if the
machinery did nothing at all, would this row still pass?**

# The TOP-LEVEL half, measured 2026-09-06 (frankS), compiler 4142d4f20747

**The same rule, one scope out, and here it is a WRONG VALUE in fifteen lines
rather than a warning on fgl.** An alias is not a class; two aliases of the same
specialization name ONE type. pxx mints one class per alias.

```pascal
program b; {$mode objfpc}{$H+}
type
  generic TBox<T> = class(TObject) V: T; end;
  TIntBox  = specialize TBox<Integer>;
  TIntBox2 = specialize TBox<Integer>;     { the SAME type as TIntBox }
var a1: TIntBox; a2: TIntBox2;
begin
  a1 := TIntBox.Create;
  a2 := TIntBox2.Create;
  a2 := a1;                                { accepted by both }
  WriteLn(a1 is TIntBox2);                 { pxx FALSE, fpc 3.2.2 TRUE }
end.
```

Assignment between them is ACCEPTED and the `is` test is FALSE, which is the
combination that makes it dangerous: the two views agree everywhere except at
the one place a program asks.

## THE CANONICAL KEY ALREADY EXISTS AND IS ALREADY CORRECT

This is the fact the nested half did not have, and it moves the fix from
"invent a keying" to "route one caller through the keying that is already
there". An INLINE specialization is minted under `Template$Args` and two of them
share identity properly; only the ALIAS spelling mints under the alias name:

| spelling | pxx `ClassName` | fpc 3.2.2 |
| --- | --- | --- |
| `var x: specialize TBox<Int64>` (twice) | `TBox$Int64`, `TBox$Int64` | `TBox<System.Int64>` ×2 |
| `var z: specialize TBox<Integer>` | `TBox$Integer` | `TBox<System.LongInt>` |
| `TIntBox = specialize TBox<Integer>` | **`TIntBox`** | `TBox<System.LongInt>` |
| `TIntBox2 = specialize TBox<Integer>` | **`TIntBox2`** | `TBox<System.LongInt>` |

`x is specialize TBox<Int64>` is TRUE (the canonical key works). `z is TIntBox`
is FALSE (the alias minted a second class). fpc answers TRUE to both.

So the shape of the fix is: mint under the canonical `Template$Args` key
ALWAYS, and register the alias name through `RegisterUClassAlias` rather than as
a class of its own — `ParseSpecialization`'s `specName` parameter is the single
place the alias name enters.

## WHY IT IS STILL PARKED, AND WHAT WOULD UNPARK IT

`ClassName` becomes `TFPGList$Integer` where it now reads `TIntegerList` — for
EVERY alias-bound specialization in fgl, rtl-generics and every consumer of
them. That is closer to fpc (which prints `TFPGList<System.LongInt>`, also not
the alias) and it is still a visible change to a value programs log and
sometimes branch on, over a population nobody has enumerated. Same reason the
nested half is parked, and now for a second gate. It wants a full tier, and the
enumeration wants the delta instrument rather than the outcome: print every
(alias, canonical) pair the change would collapse, over the test and examples
trees, before touching the mint.

## What it explains

`tgeneric16.pp`'s one remaining divergent line. The skip reason called it
"ClassName of a class inheriting a specialization"; it is not about
inheritance at all. `TIntegerStack = specialize TAdvStack<Integer>` is an ALIAS,
so fpc prints the specialization's own name and pxx prints the alias's. Same
root, and the row is not burnable until this is decided.

## The "two scopes share a spelling" hazard is NOT retired — CORRECTED 2026-09-08

**The section below says this hazard does not fire and it was wrong.** Measured
today: two ROUTINE scopes each declaring `type TRec` and
`TBoxRec = specialize TBox<TRec>` collapsed into ONE specialization, and
`ib.f.s` answered `"s": no such member` against the outer record. Fixed at
`d98d297de` under
`bug-p-a-specializations-concrete-argument-is-keyed-by-its-spelling-so-two-scopes-types-collide`.

**The measurement below was real; its REACH was the invention.** It paired a
routine-local `TRec` against a UNIT-LEVEL one — two different tables and two
different owner columns — and read as a statement about any two scopes. The
shape that fires needs the SAME KIND of scope on both sides and the SAME ALIAS
NAME as well: renaming the inner alias, or the inner type, makes it pass. That
is three names to hold still at once, which is why sampling one pair retired it.

The original section follows unchanged, because the pin-era numbers in it are
still true of what they measured.

## The "two scopes share a spelling" hazard is MEASURED AND RETIRED (2026-09-07) — SUPERSEDED, see above

This ticket's key is a NAME, so the standing worry beside it has been that two
different types sharing one spelling in two scopes would dedup to a single
specialization. frank-coordinator flagged it as the same failure surface one
layer up from a live collision in `FindTypeAlias`. **It does not fire, and the
measurement is the point rather than the reassurance.**

A routine-local `TRec` (4 bytes) and a unit-level `TRec` (16 bytes), both
specializing one template in one program:

| | inner | outer |
| --- | --- | --- |
| fpc 3.2.2 | 4 | 16 |
| pxx, compiler `4fcc6478fb08` | 4 | 16 |

Two specializations, correctly distinct, from one spelling. So the name key is
not collapsing them in the shape that reaches it — the lexical scope reaches the
mint before the name does.

**And the shape that would test it harder cannot be run: it dies earlier.** Put
a METHOD on the template and the same program stops before any dedup happens:

```
pascal26:9: error: expected ':' before '.'
  near: LongInt ; end ; function TB$87 >>> . Size :
```

A routine-local specialization's method body is spliced where the parser will
not take a method implementation — the same class of anchor defect as
[[bug-p-a-specialized-method-body-splices-into-an-illegal-place-under-circular-uses]],
and nothing to do with naming. **So what is left of the hazard is behind a parse
wall, not behind the key**, and re-opening it needs that wall gone first. Worth
stating in that order: a hypothesis retired by a green needs the green's reach
named beside it, and the reach here is "fields-only templates".

The fields-only row above is the useful residue. It is not a fixture yet; adding
one costs nothing and would stop this question being re-asked a third time.

## 2026-09-07 — the SELF-REFERENCE half is fixed; the IDENTITY half is not

Landed: a generic method may now take its own specialization as a parameter,
which is the case `tgeneric11.pp` has been skip-listed for.

```pascal
generic TList<_T> = class
  procedure Assign(Source: specialize TList<_T>);   { names its OWN specialization }
end;
type TMyIntList = specialize TList<Integer>;
...  l2.Assign(l1);   ->  no overload of Assign matches these arguments
                          argument types: (class)
```

**The cause is this ticket's cause, reached from the other side.** In
`SpecializeToBuffer`, a `specialize`-group inside the template body is collapsed
to the class under construction when its name matches. The test was
`CaseEqual(aliasNm, specName)` — and those two names are drawn from DIFFERENT
namings. `NestedSpecAlias` substitutes `_T`->`Integer` and yields the CANONICAL
key `TList$Integer`; `specName` is whatever the user wrote, here `TMyIntList`.
So the test could only succeed when the user had NOT named the specialization,
and **every alias-declared one is exactly the case where it fails.** The group
fell through uncollapsed, the stream carried a literal `specialize TList<Integer>`
that minted a SECOND class, and the argument and the parameter were then two
unrelated classes — the same "one specialization, two classes" this ticket is
about, only produced inside one template body instead of across two aliases.

The fix computes the name the class is ACTUALLY being built under —
`StreamedSpecCanonName`, `SpecializeTemplateName` + `$` + each `SpecSubValues[q]`
— and tests that FIRST, so a self-reference can never be answered by a same-named
row minted for an earlier specialization:

```pascal
aliasNm := NestedSpecAlias(tokStart, i, gEnd);
if CaseEqual(aliasNm, StreamedSpecCanonName) then aliasNm := specName;
if CaseEqual(aliasNm, specName) or NestedSpecKnown(aliasNm) then ...
```

**The discriminator that says it was the NAME and not the mechanism:** spell the
variables inline — `var l1, l2: specialize TList<Integer>` — and the identical
program compiles and runs on the compiler that refuses the aliased one, because
then the user's name IS the canonical one. Both spellings are rows in the
fixture, `test/test_a_generic_method_takes_its_own_specialization_as_a_parameter.pas`,
whose last two rows are the positive control: two specializations of one template
with DIFFERENT type arguments and different values, both read back, so a collapse
that leaked would hand the AnsiString list an Integer one. Equal arguments would
have made a leak invisible. Positive control on pin v407: the fixture fails there
with the exact reported error.

**What is NOT fixed, measured today at compiler `a7537a942c75`.**

- The two-alias identity row is UNCHANGED: `a1 is TIntBox2` still answers FALSE
  where fpc answers TRUE. This fix claims nothing about it and the row was
  re-measured rather than assumed.
- **`tgeneric16.pp` still diverges and its row STAYS.** It compiles and runs
  `rc=0`, which is the trap its own skip reason warns about; diffed against the
  fpc oracle line by line, exactly one line differs and it is the one the reason
  names — fpc `TAdvStack<System.LongInt>`, pxx `TIntegerStack`. That is this
  ticket's headline defect, untouched: an alias-declared specialization is still
  minted, and still names ITSELF, under the alias.

So the remaining work is the one the summary already states — route
`ParseSpecialization`'s `specName` through the canonical key and register the
alias with `RegisterUClassAlias`. `StreamedSpecCanonName` is a second, local
computation of that same key; when the routing lands, it should collapse into it
rather than survive beside it.

## 2026-09-08 — THE TOP-LEVEL HALF IS FIXED. The NESTED half is not, and it is the one this ticket is named for.

Landed at compiler `cd2d264c72df`. `TIntBox` and `TIntBox2`, both
`= specialize TBox<Integer>`, are now ONE class.

**Not by routing the mint through the canonical key.** That is what this ticket
proposed, and it is the change that renames every alias-bound specialization in
fgl and rtl-generics — the reason it was parked, and the reason is still good.
The smaller move is the one the defect actually asks for: when a specialization
EQUIVALENT to this one is already declared and visible here, register the new
name as a **UClass alias** of that class and mint nothing. The alias table is
where a plain `TOptionList = TList;` already lands and `FindUClass` resolves
through it, so var decls, `X.Create`, casts and `is`/`as` all reach the one
class.

**Registered as an ALIAS and deliberately NOT as a second `Specializations[]`
row.** `BufferGenericMethod` walks that table and streams each buffered method
body once per matching row, so a duplicate row would emit `TIntBox2.Foo` beside
`TIntBox.Foo` — which is the `duplicate definition …; the later body wins`
warning this ticket opens with. The bug would have been re-created by the fix.

**Equivalence is `d98d297de`'s, not a new one:** same template BY INDEX, same
arity, same argument spellings AND same `SpecArgIdentity`, asked only of rows
this scope can see (`DeclVisibleSect` + `ScopeReachesProc`). So two routines'
own `TRec` still mint two specializations; only genuinely equal ones collapse.

### The defect was worse than "answers FALSE" — measured on pin v407

```
assign  7          <- accepted by BOTH compilers, which is what hid it
is-same FALSE      <- fpc: TRUE
as-same Runtime error 219 (invalid typecast)
```

The `as` cast is a hard runtime abort, not a wrong boolean. The assignment
`a2 := a1` is accepted either way, so any probe built around passing values
around prints the same thing on a broken compiler as on a correct one.

### ClassName, which is what parked this — measured, all three

|  | first alias | second alias |
| --- | --- | --- |
| fpc 3.2.2 | `TBox<System.LongInt>` | `TBox<System.LongInt>` |
| pin v407 | `TIntBox` | `TIntBox2` |
| pxx `cd2d264c72df` | `TIntBox` | `TIntBox` |

**fpc's SHAPE, not fpc's spelling** — one type has one `ClassName`, which is the
property, and the canonical-key rename this ticket proposed would have changed
the FIRST alias's name too. Nothing here does. The fixture asserts the RELATION
(`a1.ClassName = a2.ClassName`) and not the name, so it carries no divergence
that is not this ticket's.

### What is NOT fixed

The **nested** half, which is this ticket's title and its `unest7`/`tnest8`
repro: `TEnumSpec = specialize TEnum<T>` inside a generic class is still minted
under the ALIAS, so two outer specializations still mint two classes called
`TEnumSpec` and `tnest8` still stops at
`incompatible types: cannot assign Integer to AnsiString`. Re-measured at
`cd2d264c72df`, not assumed. The two outer specializations pass DIFFERENT
arguments (`Integer`, `String`), so the collapse above never applies — that half
genuinely needs the canonical key, and `CollectHoistCandidates` already computes
it (`TI$TEnumSpec`, `TS$TEnumSpec`) behind the two gates recorded above.
`tgeneric16.pp`'s one divergent line is that half and its skip row stays.

### Fixture

`test/test_two_aliases_of_one_specialization_are_one_class.pas`
(`test_alias1class26`), differential against fpc 3.2.2, seven rows. Row 4 is the
positive control and is drawn from the population the fix changes: collapsing
two aliases is only correct while the ARGUMENTS agree, and a collapse that
ignored them answers TRUE there. It goes through `TObject` because fpc refuses
`a1 is TStrBox` at COMPILE time — "Class or Object types TBox<System.LongInt>
and TBox<System.ShortString> are not related" — so the row that must print FALSE
has no oracle written directly.
