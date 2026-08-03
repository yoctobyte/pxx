---
track: A
prio: 55
type: bug
status: done
owner: claude-AN
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

## Resolved 2026-08-03 — and it was THREE implementations, not one

The diagnosis on this ticket was exactly right (`Round(v * 10^decimals)` into an
Int64) but it named only `StrFloat`. `write(v:w:d)` does not go through
`StrFloat` at all: x86-64 and aarch64 emit the formatter INLINE
(`EmitWriteFloatFixed`), and i386 / arm32 / riscv32 call a runtime helper
(`PXXWriteFloatFixed`). Three implementations of one set of rules, and all three
had the same overflow — which is also why `WriteLn(1e16:0:5)`, an entirely
ordinary line, printed `92233720368547.75808`.

### The fix, applied identically in all three

Scale the INTEGER and FRACTIONAL parts separately. `trunc(|v|)` is exact in
Int64 below 2^63 and `|v| - trunc(|v|)` is exact too, both operands being
representable; the fraction is below 1, so scaling it by up to 10^18 cannot
overflow. One multiply and one rounding, the same quality as before for every
value that already printed correctly, and no overflow for the ones that did not.

Digits past the 18th are printed as zeros rather than guessed — a double carries
no information there, and FPC pads the same way (measured: `0.1:0:20` is
`0.10000000000000000000` on both). That also removed the runtime helper's own
`267.5:0:20` -> `267.50000000000000524288`, where 524288 is 2^19 and no part of
the value.

### A second divergence found while measuring: the ROUNDING RULE

FPC rounds `write(v:w:d)` HALF AWAY FROM ZERO; pxx used `Round`, which is
half-to-even. `0.5 / 1.5 / 2.5` at `:0:0` printed `0 / 2 / 2` where FPC prints
`1 / 2 / 3`. Fixed in all three by adding a half and truncating. This was
pre-existing and unrelated to the overflow — it only surfaced because the new
regression test compared against FPC row by row instead of against pxx's own
output.

`cvtsd2si` (the rounding sibling of `cvttsd2si`, opcode $2D vs $2C) was added to
the x86-64 text assembler along the way.

### Verified

`test/lib_writefloat_fixed.pas`, wired into `test-core`, every expectation taken
from FPC running the same program: the ticket's repro at 2, 15, 16, 17, 20 and
30 decimals, negatives, `1e15`..`1e18` at 5 and 3 decimals (the ordinary values
that overflowed), `1e-300`, the half-way rounding cases, a carry out of the
fraction into the integer part, and a `:30:5` field width. **Both** paths are
exercised: `Str` reaches `StrFloat`, `WriteLn` reaches the codegen writer, and
the point is that they agree. i386 was checked against FPC separately, so the
runtime-helper path is covered too.

`gate.sh quick` GREEN after `make stabilize` + `make pin` (the builtin units are
frozen into the pinned binary, so the fixedpoint reports A != B until the pin —
B == C exactly and the sh-A/sh-B map diff showed no proc appearing or vanishing,
which is the signature of that and not of a regression).

### Residual, filed rather than left implicit

[[compat-pascal-write-fixed-huge-magnitude-differs-from-fpc]] — `|v| >= 2^63`
and NaN/Inf still print debris on x86-64 and a full 301-digit expansion on the
helper backends, where FPC uses an exponent form. Three backends, three answers.
The real fix is to route x86-64 and aarch64 through `PXXWriteFloatFixed` too,
collapsing the three implementations into one; that needs a `width` parameter on
the helper and every call site changed together, which is its own piece of work.

## Log
- 2026-08-03 — resolved.
- 2026-08-03 — resolved, commit HEAD.
