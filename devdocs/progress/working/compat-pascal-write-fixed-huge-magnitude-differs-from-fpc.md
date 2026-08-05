---
track: A
prio: 40
type: bug
blocked-by: decide-float-fixed-output-exact-or-fpc-17-digit-cap
summary: "write(v:w:d) with |v| >= 2^63, or a NaN/Inf, still prints debris on x86-64 (9223372036854775809.00000) and diverges from FPC on i386/arm32/riscv32 (full 301-digit expansion vs FPC's exponent form)"
status: working
owner: claude-A
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


## Re-measured 2026-08-05 — the BUG half is fixed; what remains is the Track U fork

Two of the ticket's three complaints are gone, measured at HEAD:

| complaint | now |
| --- | --- |
| x86-64 prints debris `9223372036854775809.00000` | **fixed** — no saturation; the value is a real expansion |
| "three backends, three answers" | **fixed** — x86-64 / i386 / arm32 now print the IDENTICAL string |
| NaN / Inf print debris | **fixed** — ` Nan` / ` Inf` on every backend |

Fixed by today's float work: `bug-a-x86-64-writeln-fixed-saturates-at-int64`
(the Int64-scaling native emitter replaced by a shim onto `PXXWriteFloatFixed`),
`bug-a-aarch64-float-field-width-ignored` (the width parameter that made the
shim possible without losing padding), and
`bug-a-writeln-nonfinite-float-aarch64-emitters-unchecked`.

`WriteLn(1e20:0:2)` is now byte-identical to FPC on every target.

### What is left is NOT a bug — it is the exact-vs-capped question

    1e20:0:2    pxx 100000000000000000000.00          FPC 100000000000000000000.00   AGREE
    1e30:0:3    pxx 1000000000000000140737488355328.  FPC 1000000000000000000020000000000.00
    1e300:0:5   pxx 99999999999999983567616651958...  FPC  1.0E+0300

At 1e30 **neither is the exact double** — pxx prints the true value
(`1000000000000000140737488355328`), FPC prints its own approximation, because
FPC computes in Extended. At 1e300 FPC gives up on the fixed form entirely and
falls back to **exponent notation**, which is a third behaviour again.

So there is no single "FPC's answer" to match here, which is why this is now
**blocked on `decide-float-fixed-output-exact-or-fpc-17-digit-cap`**. That
decision has been updated with FPC's exponent-form fallback as evidence — it is
a third option nobody had written down.

Whichever way it goes, the implementation is one place now (`PXXWriteFloatFixed`)
rather than the three divergent backends this ticket was opened against.
