---
track: A
prio: 40
type: bug
blocked-by: []
summary: "riscv32 flushes subnormals: (1e-320 * 0.5) * 2.0 <> 1e-320, Exp(-745) returns 0 where every other target gives a subnormal, and Ln(5e-324) answers -746.52 instead of -744.44. Identical in both float modes, so it is the target's soft-float runtime, not the math unit. i386, arm32, aarch64 and x86-64 are all correct."
---

# riscv32: soft-float drops subnormals

- **Type:** bug (riscv32 backend / soft-float runtime — **Track A**). Filed by
  Track B, which found it cross-verifying `lib/rtl/math.pas` and does not edit
  the backends.
- Found 2026-08-15. **Not from the fast-float work** — identical under
  `-dPXX_FLOAT_EXACT`.

## Symptom

`qemu-riscv32-static`, both float modes:

```
1e-320 > 0?                   TRUE
(1e-320 * 0.5) * 2.0 = 1e-320?  FALSE   <- the value cannot survive a halving
Exp(-745) > 0 ?               FALSE     <- every other target: a subnormal
Ln(5e-324)                    -746.519513   correct: -744.440072
Ln(1e-320)                    -746.519513   <- same answer for a different input
```

That last pair is the tell: two different subnormal inputs produce the *same*
logarithm, because both were flushed to the same representable value on the way
in.

## Scope

| target | subnormals |
| --- | --- |
| x86-64, i386, arm32, aarch64 | correct |
| **riscv32** | **flushed** |

`test/lib_math_fast_tolerance.pas` carries the two rows that catch this
(`exp-denormal-not-flushed`, `ln-denormal-arg`). They pass on every target
except riscv32 and are deliberately NOT guarded with an ifdef — the assertion is
correct IEEE behaviour and the target is what is wrong. That suite runs natively
in `lib-test`, so this does not red anything today; it will surface if the lib
tests are ever added to the cross matrix.

## Fix direction

The riscv32 float path is soft-float. Find whether the runtime's add/mul/scale
helpers handle the subnormal exponent case at all, or whether they assume a
normalized mantissa with the implicit leading 1. The `(x*0.5)*2.0` round-trip
failing points at multiply/scale rather than at conversion.

## Gate

`make test` + self-host byte-identical, plus the probe above under
`qemu-riscv32-static` matching what arm32 prints, plus
`test/lib_math_fast_tolerance.pas` cross-built for riscv32 reaching
`MATHFAST OK`.
