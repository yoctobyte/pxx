---
track: A
prio: 55
type: bug
---

# `WriteLn(x:0:17)` prints garbage

- **Type:** bug (float formatting, silent wrong output) — **Track A**
  (`compiler/builtin/builtin.pas`; re-laned from B 2026-08-02, see below)
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

## Re-laned to Track A 2026-08-02 — the code is not in `lib/rtl`

Filed under B on the assumption it was RTL float formatting. It is not:
`write(v:width:decimals)` lowers to `StrFloat` in
**`compiler/builtin/builtin.pas:714`**, and the overflow is right there —

```pascal
pw := 1;
for i := 1 to decimals do pw := pw * 10;
scaled := Round(v * pw);              { round-to-nearest, Int64 }
```

`compiler/**` is Track A's ground and Track B does not edit it, so the ticket
moves rather than being fixed under B.

**Re-measured at this commit**, `2.675*100.0` for N = 0..17 (so the ticket's
own speculation can be replaced with the real boundary):

| N | output |
| --- | --- |
| 0..15 | correct (`268` … `267.500000000000000`) |
| 16 | `267.5000000000000000` — **correct**, contrary to this ticket's guess |
| 17 | `-92.-23372036854775808` — garbage, and now also sign-mangled |

So the wall is at 17 only, not 16: `pw` is `Int64` and `10^17` still fits
(`1e17 < 9.22e18`), so N=16 survives; at N=17 the *product* `267.5 * 1e17`
= 2.675e19 is what overflows. The negative-sign debris in the current output
differs from the `92.23372036854775808` originally recorded.

## Related — the exact machinery now exists

[[bug-b-floattostrsig-caps-at-15-significant-digits]] landed exact decimal
expansion for doubles in `lib/rtl/sysutils.pas` (`FloatToStrExact` /
`FloatToStrShortest`, backed by integer-only digit generation). The same
approach applies here and avoids the scaled multiply entirely: generate the
exact digits and place the point, rather than computing `Round(v * 10^N)`.
`compiler/builtin` cannot use `sysutils`, so this is a port of the algorithm,
not a call — but it is a known-good algorithm with a verified oracle sweep
behind it rather than a fresh design.

## Gate

`WriteLn(x:0:N)` for N = 0..17 over a spread of magnitudes, each checked against
the exact decimal value (`Decimal(x)` in CPython is a convenient oracle).
