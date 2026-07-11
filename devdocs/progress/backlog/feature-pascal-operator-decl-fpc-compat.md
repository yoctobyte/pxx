---
prio: 44
---

# operator declarations: FPC named-result syntax + `/` in the op set

- **Type:** bug/gap (Pascal frontend, small) — Track P (shared parser.inc,
  A-gated)
- **Status:** backlog — filed 2026-07-11 while scoping
  [[feature-pascal-complex-numbers-ucomplex]]; widened same day after
  verifying the two compilers accept EXACTLY complementary syntax
- **Owner:** —

## Gap 1 — named-result form (the FPC-compat one)

Verified 2026-07-11 on stock FPC 3.2.2 vs pxx:

```pascal
operator + (a, b: T) z: T;  begin z.v := ...        { FPC: ONLY this parses }
operator + (a, b: T): T;    begin Result.v := ...   { pxx: ONLY this parses }
```

Zero overlap → no operator-using source compiles on both. Since pxx is
FPC-faithful by default, pxx should ACCEPT the named-result form too (keep
our Result form as the dialect extension): in `ParseOperatorDef`
(parser.inc ~1315), when the token after the closing `)` is an ident
followed by `:`, treat `ident` as the result variable — cheapest lowering:
inject it as an alias of Result (or synthesize `var z: T` + `Result := z`
epilogue; alias is cleaner since the body may `Exit` early). Everything
else (token-stream rewrite to `__op__NN`) stays.

## Gap 2 — `/` not declarable

`ParseOperatorDef` op set is `+ - * div = <> < <= > >=`; the USE site
(term parser ~6945) already resolves tkSlash via FindOpOverload, so
declaring `operator /` is the only missing half. Add tkSlash (and decide
`mod` while there — bignum wants it, [[feature-lib-bignum-operators]]).

## Payoff

FPC's ucomplex (and any FPC operator library) ports without rewriting
declaration heads; `z1 / z2`, `v / scalar` become natural. Unblocks the
clean version of [[feature-pascal-complex-numbers-ucomplex]] and
[[feature-lib-vecmath]].

## Gate

`make test` + self-host fixedpoint byte-identical. Tests: named-result
operator (with early Exit in body), `/` overload, both-form mix in one
program; negative: junk between `)` and `:`.
