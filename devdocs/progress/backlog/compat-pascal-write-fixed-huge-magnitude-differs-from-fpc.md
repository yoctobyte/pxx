---
track: A
prio: 40
type: bug
summary: "write(v:w:d) with |v| >= 2^63, or a NaN/Inf, still prints debris on x86-64 (9223372036854775809.00000) and diverges from FPC on i386/arm32/riscv32 (full 301-digit expansion vs FPC's exponent form)"
---

# `write(v:w:d)` on a huge magnitude: three backends, three answers, none FPC's

- **Type:** bug (residual of
  [[bug-b-writeln-float-with-17-decimals-prints-garbage]]) — **Track A**
- **Found:** 2026-08-03, measured against FPC while fixing that ticket. The
  ordinary range is now FPC-identical on every backend; this is what is left.

## Measured

```pascal
WriteLn(1e300:0:5);
WriteLn((1.0/0.0*0.0):0:3);    { NaN }
```

| | `1e300:0:5` | NaN |
| --- | --- | --- |
| FPC | ` 1.0E+0300` | `Nan` |
| pxx x86-64 | `9223372036854775809.00000` | `-9223372036854775809.000` |
| pxx i386 / arm32 / riscv32 | the full 301-digit fixed expansion | (untested) |

The x86-64 answer is debris — `cvttsd2si` saturates to `Int64`'s limit, and its
digits get printed. The runtime-helper backends produce the exact fixed
expansion, which is *true* but is neither FPC's nor x86-64's.

**Three backends printing three different texts for one program is the part
that matters most**, more than which of them matches FPC.

## Why it was left

The ordinary range — everything with `|v| < 2^63` — is now FPC-identical on
both the codegen path and the runtime helper, which is what the parent ticket
was about. Fixing this corner needs one of:

- a runtime magnitude test in `EmitWriteFloatFixed` branching to the scientific
  writer, which doubles the emitted code at every `write(v:w:d)` call site; or
- routing x86-64 (and aarch64) through `PXXWriteFloatFixed` like the other three
  backends — the right answer, and it also collapses THREE implementations of
  one formatter into one, but the helper takes no `width` argument, so its
  signature and every backend's call site have to change together.

The second is the real fix and is worth doing on its own terms.

## Note on FPC as the oracle here

FPC's own answer is type-dependent and not worth matching digit for digit: a
literal `1e300` is Extended and prints a FOUR-digit exponent (` 1.0E+0300`),
while the same value in a `Double` variable prints three (` 1.2E+300`). Match
its SHAPE (fall back to an exponent form) rather than its exact spelling.

## Gate

A Pascal test over `1e300`, `1e60`, `DBL_MAX`, `NaN`, `+Inf`, `-Inf` and
`-1e300` at several `:w:d`, run on x86-64, i386, arm32 and riscv32, asserting
all four backends produce the SAME text — and that the text is an exponent form
rather than a fixed expansion, as FPC does.
