---
track: A
prio: 40
type: bug
---

# A wide unsigned literal boxed into a Variant stores the wrapped value

`v := 18446744073709551615` stores **-1**. fpc 3.2.2 stores
18446744073709551615. Silent, no diagnostic, plausible number.

## Repro

```pascal
program vbox;
var v: Variant;
begin
  v := 18446744073709551615; writeln(v);   { pxx: -1        fpc: 18446744073709551615 }
  v := 9223372036854775808;  writeln(v);   { pxx: -9223...  fpc: 9223372036854775808  }
  v := 9223372036854775807;  writeln(v);   { both correct — outside the band }
end.
```

Measured at compiler `b31b9b1821c1`, both compilers on the same source.
Confined to the band `[2^63, 2^64)`: below it the Int64 reading is right, and
at or above 2^64 the literal keeps `tyInt64`, stays in `IsWideIntLit`, and
routes through the promo runtime correctly.

Only the ASSIGNMENT differs. `v + 0` answers -1 under **both** compilers, so
the operand path is not in scope here.

## Cause

Same one as `regression-test-core-test-promoint-bitwise`: `10e670503` retags
every decimal in `[2^63, 2^64)` to `tyUInt64` at the literal's creation site,
which takes it out of `IsWideIntLit`, which is what the variant boxing arm
(`compiler/ir.inc`, the `IR_VAR_BOX` operand arms and the assignment arm above
them) asks before routing a wide literal through `PXXPromoBoxedVariantAddr`
instead of boxing the wrapped machine int. A variant carries no unsignedness,
so `tyUInt64` as the source kind does not save it.

## Why the obvious fix is wrong, measured

Widening those arms to the digits-only predicate (`WideLitHasDigits`, added
2026-09-06) **makes an ordinary Pascal program that never mentions PromoInt
fail to compile**:

```
pascal26:7: error: promotable int: runtime helper PXXPromoFromStr not found
                   (promocore unit not loaded)
```

Measured — I wrote that fix, built it, and reverted it. That is a worse answer
than the wrong value and it is the exact condition `10e670503` exists to
remove. Above 2^64 the same routing is worth it because no 64-bit reading
exists at all; inside the band one does.

**So the repair belongs on the variant side, not in the predicate** — either a
variant that carries unsignedness, or a box-by-source-kind that honours
`tyUInt64`. Both are Track A design calls beyond the predicate split.

## Trap for whoever takes it

A probe for this MUST NOT declare a `PromoInt` anywhere. Doing so loads
promocore and the promo-runtime route silently starts working, so the broken
fix above reads as correct. That is how it got past me: my band probe declared
`p: PromoInt` for unrelated rows and certified an arm that fails in every
program without one.

Found while fixing `regression-test-core-test-promoint-bitwise`; not a
regression in the sense of a working thing broken — before `10e670503` this
shape did not compile at all.
