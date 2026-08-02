---
track: B
prio: 55
type: bug
---

# `WriteLn(x:0:17)` prints garbage

- **Type:** bug (RTL float formatting, silent wrong output) — **Track B**
  (`lib/rtl`)
- **Found:** 2026-08-02, while probing `round()` against the CPython oracle —
  the probe's own diagnostic output was wrong, which is how it surfaced.

## Measured

```pascal
var y: Double;
y := 2.675 * 100.0;        { = 267.5 }
WriteLn(y:0:2);            { 267.50                  correct }
WriteLn(y:0:15);           { 267.500000000000000     correct }
WriteLn(y:0:17);           { 92.23372036854775808    WRONG   }
```

`9223372036854775808` is `2^63`, so the fixed-point formatter is almost
certainly scaling by `10^17` into an **Int64** and overflowing: `267.5 * 1e17`
is ~`2.675e19`, well past `Int64`'s `9.22e18`.

16 decimals is worth checking too — `1e16 * 267.5` already exceeds Int64.

## Why it matters

Silent. A diagnostic that asks for more precision gets a plausible-looking
number that is pure overflow debris, which is the worst shape for something
whose entire job is to let you inspect a value. It is also exactly the range a
float-precision investigation reaches for.

## Fix shape

Clamp or reject a precision the Int64 path cannot represent, or format the
fractional digits without a single scaled multiply. Related:
[[bug-b-floattostrsig-caps-at-15-significant-digits]] — the same routine family,
and the same underlying "we scale a double and hope" approach.

## Gate

`WriteLn(x:0:N)` for N = 0..17 over a spread of magnitudes, each checked against
the exact decimal value (`Decimal(x)` in CPython is a convenient oracle).
