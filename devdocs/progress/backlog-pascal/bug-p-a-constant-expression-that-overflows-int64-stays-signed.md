---
track: P
prio: 40
type: bug
blocked-by: []
summary: "A constant EXPRESSION whose value lands between High(Int64) and High(QWord) keeps tyInt64, so `if (high(int64)+100) > 0` takes the NEGATIVE arm where fpc 3.2.2 takes the positive one — a silent wrong branch on a constant the programmer wrote out in full. The LITERAL half of this is fixed (10e670503: a decimal literal above High(Int64) is tagged tyUInt64 at its creation site); the FOLD half is not, because pxx has no signed/unsigned tag on constant arithmetic at all — ConstEval returns a bare Int64 and the expression path types `tyInt64 + tyInteger` as tyInt64 by kind. Blocks `toperator6.pp`, whose whole subject is that promotion: it declares `operator :=(qword)` beside `operator :=(int64)` and `value := high(int64)+100` must select the QWord one. Second, smaller half in the same area: conversion-operator ranking reads a literal's STATIC kind, not its by-value kind, so `b := 200` picks the Int64 overload where fpc picks the Byte one."
status: backlog
owner: unassigned
---

# A constant expression that overflows Int64 stays signed

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
