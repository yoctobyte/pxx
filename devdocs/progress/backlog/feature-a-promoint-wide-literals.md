---
track: A
prio: 60
type: feature
---

# PromoInt cannot be initialised from a literal wider than Int64

Found while differential-testing stage 3 of [[feature-a-promotable-int]]
against CPython. Blocked on
[[bug-a-integer-literal-out-of-range-wraps-silently]].

## Repro

```pascal
var x: PromoInt;
begin
  x := 9258932120814846640;   { one more than Int64 can hold }
  Writeln(x);
end.
```

Prints `-9187811952894704976`. The heap tier is working — `a := 1; for i := 1
to 30 do a := a * i` is exact — but a value cannot be WRITTEN DOWN past Int64,
because the literal is folded to an Int64 by the lexer long before the promo
store sees it.

So the type can compute in its full domain but not express it, which is a gap
a user meets on their first line.

## Shape

Needs the literal's TEXT, not its folded value:

1. The lexer must flag a decimal literal that did not fit (the sibling bug
   above adds that detection) and keep its digit span.
2. The parser must carry that through to the AST node.
3. The promo store lowers such a literal to a new `PXXPromoFromStr(dst,
   '<digits>')` rather than `PXXPromoFromInt`. The ticket's own coercion matrix
   already calls for exact decimal in both directions, so this entry point is
   wanted regardless — `PXXPromoToStr` exists, its inverse does not yet.

Same applies to a wide literal appearing in an EXPRESSION with a promo operand,
not only in a direct assignment.

## Gate

Round-trip: a wide literal in, `Writeln` out, byte-equal to CPython's rendering
of the same integer; plus arithmetic starting from a wide literal. `--tier
quick` + self-host byte-identical.
