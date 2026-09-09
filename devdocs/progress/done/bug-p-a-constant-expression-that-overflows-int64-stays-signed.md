---
track: P
prio: 40
type: bug
blocked-by: []
summary: "A constant EXPRESSION whose value lands between High(Int64) and High(QWord) keeps tyInt64, so `if (high(int64)+100) > 0` takes the NEGATIVE arm where fpc 3.2.2 takes the positive one — a silent wrong branch on a constant the programmer wrote out in full. The LITERAL half of this is fixed (10e670503: a decimal literal above High(Int64) is tagged tyUInt64 at its creation site); the FOLD half is not, because pxx has no signed/unsigned tag on constant arithmetic at all — ConstEval returns a bare Int64 and the expression path types `tyInt64 + tyInteger` as tyInt64 by kind. Blocks `toperator6.pp`, whose whole subject is that promotion: it declares `operator :=(qword)` beside `operator :=(int64)` and `value := high(int64)+100` must select the QWord one. Second, smaller half in the same area: conversion-operator ranking reads a literal's STATIC kind, not its by-value kind, so `b := 200` picks the Int64 overload where fpc picks the Byte one."
status: done
owner: frankD
---

# A constant expression that overflows Int64 stays signed

> ## DONE 2026-09-09 (frankD) — the PROMOTION half. The second, smaller half is NOT done.
>
> `high(int64)+100 > 0` now takes the positive arm, and **fpc's own
> `toperator6.pp` burns**: `rc=2` under the pin (the `int64` operator was
> selected, `halt(2)`), `rc=0` after, matching fpc. That row's whole subject is
> this promotion.
>
> **I nearly reported it as non-discriminating.** Both compilers *compile*
> `toperator6.pp` before and after — the assertion is in its exit code, via
> `halt(1)`/`halt(2)`, and I compared compile success first. The corpus ticket
> warns that exit-clean is not correct because the runner compares exit codes;
> the inverse bites too, and a row whose verdict IS the exit code says nothing
> at all when you only build it.
>
> ### Where it went, and why it is small
>
> `ParseSimpleExpr`'s ordinal arm, beside the rule that was already there for
> the operand-tag case (*"a non-negative literal paired with a QWord operand
> joins the unsigned domain"*). The new arm reaches the same domain **by VALUE**:
> both operands non-negative constants and the Int64 sum carrying into bit 63,
> which for two Int64-representable non-negatives can only mean the true value
> is in `[2^63, 2^64)` — exactly a QWord, and it cannot have wrapped further.
> Ordered BELOW the two tag arms so an already-unsigned operand keeps taking
> them.
>
> The ticket's plan assumed this needed a signed/unsigned tag threaded through
> constant arithmetic, like FPC's `Tconstexprint.signed`. It did not: the
> **existing** `TypeArithmeticResultOp(tyUInt64, tyUInt64, op)` path already
> produces the right type, so the whole change is deciding when to enter it.
>
> ### What is NOT done, stated so nobody reads this as the whole ticket
>
> - **`*` is not covered.** A product can wrap PAST 2^64, where the value is
>   representable in neither reading and `lv*rv < 0` stops meaning "landed in
>   the unsigned band". `high(int64)*2` is still signed. Narrower coverage, not
>   an inconsistency — nothing promotes in one direction while failing to demote
>   in the other, which is the pairing this ticket warned about.
> - **`-` needed nothing**, and that is a measurement, not an assumption: two
>   non-negative operands cannot subtract into the sign bit, and a left operand
>   already tagged `tyUInt64` is carried by the QWord arm. `high(int64)+100-200`
>   stays unsigned and positive; it is a fixture row.
> - **THE SECOND, SMALLER HALF IS UNTOUCHED** — the one this ticket's own summary
>   names last: `FindOpConvToDest` is handed `ASTTk[rhs]`, so a conversion
>   operator ranks a literal by its STATIC kind and `b := 200` picks the Int64
>   overload where fpc picks the Byte one. That is a different site and a
>   different rule (rank by VALUE, as `LiteralIntKind` already does for call
>   arguments). **Filed as
>   [[bug-p-conversion-operator-ranking-reads-a-literals-static-kind-not-its-value]]**
>   rather than left inside a `done/` ticket, so `ready` can hand it to
>   somebody — and carrying the parent's warning that `LiteralIntKind` takes an
>   `Int64` and so cannot even be passed a value in the unsigned band. I have
>   NOT re-measured that observable at HEAD; it is frankS's from 2026-09-06.
>
> ### Fixture
>
> `test/test_const_fold_overflows_into_qword.pas`, 10 rows, `.expected` is fpc's
> own output. Three rows fail under the pin and pass after; **six are identical
> on both sides on purpose** — including `stored` and `lit`, because the VALUE
> was always right and a fixture built from stores would have been green
> throughout. `gate.sh quick` GREEN, `converged after 1 round(s)`, compiler
> `2a9e5179428f`.


- **Found:** 2026-09-06 (frankS), on `toperator6.pp` from the FPC-testsuite
  corpus ([[feature-pascal-corpus-fpc-testsuite]]).
- **Measured at compiler `4b22a668e6ab`** against fpc 3.2.2.

## The observable, without any operator overloading in sight

```pascal
var q: qword;
begin
  q := high(int64)+100;
  Writeln(q);                                       { both: 9223372036854775907 }
  if (high(int64)+100) > 0 then Writeln('positive') else Writeln('negative');
end.
```

```
fpc:  9223372036854775907 / positive
pxx:  9223372036854775907 / negative
```

**The VALUE is right and the TYPE is wrong**, which is why this hides: every
store of the constant into a QWord gives fpc's bytes, and only a question that
asks about its type — a comparison, an overload — reads back the signed view.

## Why the literal fix does not reach it

`10e670503` tags a decimal LITERAL above `High(Int64)` as tyUInt64 at its
creation site (ParseFactor) and carries the same fact through the const
evaluator (`CEOrdTk`). `high(int64)+100` is neither: it is a FOLD, and pxx has
nowhere to record that a fold went unsigned. `ConstEval` returns a bare `Int64`;
the expression path types the binop from the two operand KINDS
(tyInt64 + tyInteger = tyInt64) and never looks at the result value.

FPC does have somewhere: `Tconstexprint` carries a `signed` flag beside the
value and flips it on overflow. `toperator6.pp` is not a coincidence here — the
record it declares is a hand-rolled copy of exactly that type.

## What a fix has to decide

- Where the tag lives. `CEOrdTk` is the existing precedent on the const-eval
  side and already carries `TkIsUnsigned64` through `ConstEvalTerm`/`Add`; the
  EXPRESSION path has no equivalent and is the larger half.
- `+ - *` overflowing into the sign bit with both operands non-negative is the
  promotion; `-` going negative is the demotion. Getting one without the other
  is worse than neither.
- Do NOT reach for `LiteralIntKind` (symtab.inc): it takes `v: Int64`, so a
  value above `High(Int64)` cannot even be passed to it, and it caps at
  `tyInt64` and never returns `tyUInt64`.

## The second, smaller half — ranking reads the static kind

Independent of the fold, and fixable on its own. `FindOpConvToDest` is handed
`ASTTk[rhs]`, so an integer literal ranks as its STATIC kind. FPC types the
literal BY VALUE first (the rule pxx already implements for CALL arguments, via
`LiteralIntKind` in `pasparser_lval.inc`) and ranks that. Measured, two
conversion operators to one destination:

```
                       fpc      pxx
operator :=(integer) / :=(int64)
  a := 10             integer   integer
  a := 200            integer   integer
  a := 5000000000     int64     int64
operator :=(byte)    / :=(int64)
  b := 10             int64     int64
  b := 200            byte      int64     <-- diverges
  b := 300            int64     int64
```

One row, and it names the rule: 200 types as Byte by value, which is an EXACT
hit on the byte parameter; 10 types as ShortInt, which prefers the same-signedness
Int64 over the unsigned Byte; 300 types as Word, which the Byte parameter cannot
hold. So `OpConvSourceRank` (symtab.inc) needs the source kind BY VALUE, a
"parameter can hold the value" filter, and a narrower-wins tiebreak. Every other
row above already agrees, so the change is aimed at one row and must not move
the other five.

## Not taken

`toperator6.pp` stays skip-listed; its skip reason names both halves. Banked
rather than microfixed — the fold half is a representation change, not a patch.
