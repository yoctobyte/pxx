---
track: P
prio: 40
type: bug
blocked-by: []
status: open
owner: frankS
found-by: frankS
created: 2026-09-08
summary: "An EXPLICIT cast to a frozen-string type with no exact-capacity `Explicit` operator falls back to the generic **Explicit** conversion; fpc 3.2.2 falls back to the generic **Implicit** one. `s40 := TString40(t)` with Explicit and Implicit operators declared for String[80], String[90] and ShortString runs `ShortString Explicit` here and `ShortString Implicit` there. Measured, not inferred: toperator91 asserts `ImplicitShortString = 1` on the line immediately after and halts(3) on it, which is exactly where pxx stops. Sole remaining cause of that corpus row — the declaration and store halves of the capacity family both landed 2026-09-08, burning toperator94 and making toperator92/95 refuse for fpc's reason. Once this rule holds, toperator91's six implicit assignments follow from the generic-preference rule already in place, so this is the whole row."
---

# An explicit cast with no capacity match falls back to the wrong conversion operator

```pascal
{ toperator91.pp, reduced }
class operator TTest.Explicit(const a: TTest): ShortString;  { pxx picks this }
class operator TTest.Implicit(const a: TTest): ShortString;  { fpc picks this }
...
s40 := TString40(t);            { no Explicit operator has capacity 40 }
if ImplicitShortString <> 1 then Halt(3);
```

An explicit cast writes its destination, so capacity discriminates among the
`Explicit` operators — that half landed 2026-09-07 and `TString80(t)` /
`TString90(t)` reach their own operators. What is unsettled is the FALLBACK when
no Explicit operator has the destination's capacity. pxx takes the generic
Explicit one (`OpConvResultCapRank`'s generic-fallback rank, which exists
because removing it segfaulted); fpc takes the generic Implicit one.

## Why it was split out rather than fixed alongside

It changes the explicit-cast fallback path, and that path has a live hazard with
a dated cost: `s40 := TString40(t)` with only a ShortString conversion declared
once fell through to a raw record-to-string store and SEGFAULTED, where fpc uses
its ShortString overload. `OpConvResultCapRank` in `symtab.inc` carries that
note. Any change here must keep a fallback — the question is only WHICH operator
it lands on, never whether there is one.

## The control already exists

`test/test_conversion_operator_result_capacity_is_part_of_its_identity.pas` pins
the explicit-cast behaviour that must survive, and `toperator91.pp` is the row
that goes green. Take them together.
