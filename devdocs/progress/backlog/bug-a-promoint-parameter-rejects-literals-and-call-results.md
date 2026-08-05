---
track: A
prio: 45
type: bug
summary: "A PromoInt PARAMETER accepts only a variable: `f(12)` is 'no overload matches' and `f(g())` is 'by-reference argument must be a variable'. Every other numeric parameter takes both"
---

# A `PromoInt` parameter takes only a variable

- **Type:** bug — Track A (promotable-int parameter passing)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** Track A, while verifying the fix for
  `bug-a-promoint-function-result-crashes`. Both shapes were needed to write
  that ticket's own test and neither compiles.

## Repro

```pascal
function viaOp(n: PromoInt): PromoInt; begin Result := n + 0; end;
function mk: PromoInt; begin Result := 12; end;
var p: PromoInt;
begin
  p := mk;
  writeln(viaOp(p));    { OK — a variable }
  writeln(viaOp(12));   { error: no overload of viaOp matches these arguments
                                 argument types: (Integer) }
  writeln(viaOp(mk));   { error: by-reference argument must be a variable }
end.
```

Both are ordinary calls. `f(12)` and `f(g())` work for `Integer`, `Int64`,
`Double` — every other numeric parameter type — so a promo parameter is the odd
one out, and the two errors say different things about what is really one gap.

## Why

A promo parameter is by-REFERENCE (the value is a `{tag, payload}` slot and the
callee needs its address), so:

- **a literal** has no slot, and nothing materialises one; and the overload
  matcher does not consider Integer→PromoInt a conversion, hence the
  "no overload" wording rather than a by-ref complaint;
- **a call result** has no slot the caller owns at the point of the call,
  hence the by-ref complaint.

Both want the same thing: a caller-side temp holding the promo value, exactly
as `IRLowerCallArg` already materialises for a by-value record argument. That
machinery exists; the promo path does not reach it.

## Why it matters

Arbitrary-precision arithmetic is most useful at the boundary — `Fact(20)`,
`Pow(base, 64)`, `f(g(x))`. Requiring a named variable for every promo argument
makes the type awkward exactly where it should be natural, and pushes callers to
spell out temporaries the compiler should mint.

## Related

- `bug-a-promoint-function-result-crashes` — the RESULT half, fixed (promo joins
  `RetViaHiddenDest`). This is the ARGUMENT half and is untouched by it.
- `bug-a-promoint-parameter-32bit-by-ref-indirection-hangs` — a different
  promo-parameter defect on 32-bit.
- `decide-promoint-rvalue-representation` — the design note behind "a promo
  rvalue is the slot address", which is what makes both cases need a temp.
