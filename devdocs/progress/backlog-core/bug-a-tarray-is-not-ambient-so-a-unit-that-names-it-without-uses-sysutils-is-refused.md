---
slug: bug-a-tarray-is-not-ambient-so-a-unit-that-names-it-without-uses-sysutils-is-refused
track: A
type: bug
prio: 40
status: backlog
created: 2026-09-06
found-by: frankB
owner: ""
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
