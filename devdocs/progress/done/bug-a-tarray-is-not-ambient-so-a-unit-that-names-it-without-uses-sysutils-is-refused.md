---
slug: bug-a-tarray-is-not-ambient-so-a-unit-that-names-it-without-uses-sysutils-is-refused
track: A
type: bug
prio: 40
status: done
created: 2026-09-06
found-by: frankB
owner: frankS
blocked-by: []
title: "`TArray<T>` lives in SysUtils, FPC has it in System, and the whole fpc-testsuite population names it without `uses SysUtils`"
summary: "`type TRec = record A: TArray<byte>; end;` with no `uses` compiles and runs under fpc 3.2.2 and is refused here with `unknown type: TArray`. FPC declares TArray<T> in the SYSTEM unit, so it is ambient with no `uses` at all; pxx has no lib/rtl/system.pas and its ambient types are compiler-side, which is why this is Track A and not a lib move. MEASURED 2026-09-06 at 9341b19ac: of the SIX fpc-testsuite files naming TArray<>, ZERO use SysUtils (trtti12, trtti16, tarray12, tarray18, tarrconstr5, ttbitconverter). The sysutils.pas comment that placed it there claimed the SysUtils home 'covers every real consumer' on the strength of all seven rtl-generics files using SysUtils -- true, checked, and inverted in the other corpus 7/7 against 0/6. The difference is structural, not luck: rtl-generics code uses generic COLLECTIONS which need SysUtils anyway, while testsuite files exercise TArray ITSELF and carry no more uses than the feature requires -- so the population that cannot get it here is exactly the population a conformance run is made of. NOT the specialisation-parse defect it was found beside: that one is fixed and refuses by name in field, var and class position."
---

# `TArray<T>` is not ambient

```pascal
program p; {$mode delphi}
type TRec = record A: TArray<byte>; B: Integer; end;
var r: TRec;
begin r.B := 5; WriteLn(r.B); end.
```

`fpc -Mdelphi` compiles and prints 5. pxx: `unknown type: TArray`. Adding
`uses sysutils;` makes pxx agree.

## Why it is Track A and not a one-line lib move

`lib/rtl/sysutils.pas` says it, and it is right: **pxx has no
`lib/rtl/system.pas`** — its ambient types are compiler-side. So "put it where
FPC puts it" is a compiler change, not a unit change, which is the whole reason
the original fix chose SysUtils.

## The population, and why the original check could not have seen it

| corpus | files naming `TArray<>` | of those, `uses SysUtils` |
| --- | --- | --- |
| rtl-generics | 7 | **7** |
| fpc-testsuite | 6 | **0** |

Both numbers are real and the first was measured honestly. **The inversion is
structural:** rtl-generics code uses generic COLLECTIONS, which pull in SysUtils
for other reasons, so `TArray` arrives free and no file has to ask for it.
Testsuite files exercise `TArray` ITSELF and deliberately carry no more `uses`
than the feature under test requires. So the corpus that shows 7/7 is the one
where the dependency is invisible, and the corpus that shows 0/6 is the one a
conformance run is made of.

**A census over the corpus you have is a census over the habits of the code that
corpus is made of.** Neither number is wrong; the sentence that joined them to
"covers every real consumer" is.

## Done when

The program above compiles with no `uses` clause, `uses sysutils` still works
and does not double-declare, and the six testsuite files stop failing on this
name. Whether the ambient declaration is a compiler-side builtin or a real
`lib/rtl/system.pas` is the design question and is not settled here.

# FIXED 2026-09-06 (frankS), compiler d674faa3ea21

`compiler/builtin/sysgenerics.pas` — a six-line unit holding the generic types
FPC declares in **System** — is injected ambiently from ParseProgram's token
pre-scan when the program's tokens contain the identifier `TArray`, the same
door `math`, `builtinwide`, `softfloat` and `wasibackend` come through.

**A unit rather than a compiler-side registration**, because a template is a
NAME plus a TOKEN RANGE (`Templates[]`): registering one without source means
synthesising tokens, and a six-line unit is the same thing spelled in the
language, with every existing import path working on it unchanged.

**SysUtils KEEPS its declaration.** The pre-scan sees the PROGRAM's tokens and
nothing else — builtinwide's note in `pasparser_prog.inc` records the same
limit — so a UNIT naming TArray while the program does not (rtl-generics'
`ToArrayImpl`, the original report) triggers nothing here. The two populations
are disjoint and each is covered by exactly one of the two declarations. Two
templates of the same name coexist: verified, both spellings resolve with
SysUtils loaded, and a specialization of `array of T` is a STRUCTURAL type
rather than a minted class, so it carries none of the identity trouble a
duplicated generic CLASS would
([[bug-p-a-nested-specialization-is-named-by-its-alias-so-one-name-serves-every-outer-specialization]]).

## THE HALF THAT WAS NOT THE TEMPLATE

Injecting the unit was not enough, and the failure looked nothing like the
cause. With the injection alone, a probe at the injection site printed
`tmplcount=1 find=0` — the template registered AND nameable — while the same
compile answered `unknown type: TArray` two lines later. An explicit
`uses sysgenerics` worked, which is what isolated it.

**Importing a template is two things, and an ambient load gets one.** A USE of
an imported template — Delphi's bare `TArray<T>` and objfpc's inline
`specialize TArray<T>` alike — is rewritten into an alias declaration by
`DelphiRewriteGenericUses`, and the sweep that runs it over imported templates,
`DesugarImportedDelphiGenericUses`, is called **from the end of ParseUsesClause**
— which `ParseUsesUnitAmbient` never enters. The injection site now calls it.

## The spelling in the unit is load-bearing

`TArray<T> = array of T;` under `{$MODE PXX}` (sysutils' own spelling) serves
BOTH consumer spellings. Written as `generic TArray<T> = array of T` it compiles
and then refuses the Delphi spelling at the use site with `unknown type:
TArray`. Measured both ways.

## Measured

Fixtures, all three byte-identical against fpc 3.2.2 and **none of them with a
`uses` line for this**: `test_tarray_is_ambient_with_no_uses_clause.pas` (result
position, record-field position, two argument types, `r := nil`),
`test_tarray_is_ambient_in_delphi_mode_and_yields_to_a_local_one.pas`, and
`test_a_program_declaring_its_own_tarray_shadows_the_ambient_one.pas` — the
control that matters more than the feature, since the injection is parsed before
the program's declarations and must lose to them.

Conformance: the wall moved on every row the ticket named. `tarray18` 37 -> 46,
`tarrconstr5` 14 -> 47, `trtti12` -> 22, `trtti16` -> 27; `tarray12` compiles.
None of the four burns yet — each now stops on something else, and their skip
reasons are updated to say what.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
