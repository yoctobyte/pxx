---
track: F
type: bug
prio: 25
status: open
found: 2026-08-31
found-by: frankA
summary: "WriteLn of a Double on hosted xtensa prints 10 significant digits and a 2-digit exponent (3.500000000E+00) where every other target prints 17 and 3 (3.5000000000000000E+000). The VALUES are correct -- this is digit count and exponent width only. Last remaining real divergence in the hosted-xtensa differential."
---

# xtensa formats a Double with Single-width digits and a 2-digit exponent

Measured at binary `b91c0ceab90b`, commit `d702b0641`, via
`test/test_cross_float.pas` against the x86-64 oracle:

```
xtensa            oracle
 3.500000000E+00   3.5000000000000000E+000
-5.000000000E-01  -5.0000000000000000E-001
 3.000000000E+00   3.0000000000000000E+000
 7.500000000E-01   7.5000000000000000E-001
```

**The values are right.** 3.5, -0.5, 3.0, 0.75 all round-trip correctly. What
differs is the *presentation*: 10 significant digits vs 17, and a 2-digit
exponent field vs 3. That is the shape `Write` uses for a **Single**, applied to
a Double — so the likely cause is the formatting path selecting its width from
something that is `tySingle` on this target, rather than a precision loss in the
arithmetic.

**Why this is F and not a plain bug** (`rank the mechanism, never the datatype`):
the mechanism *is* float formatting — digit count and exponent form — which the
2026-08-19 ruling puts in F explicitly. It is not a crash, a wrong value, or
control flow that merely lives in float code. Hence `float/`, which `ready` and
`next` do not scan, and prio 25.

## Bound

Hosted xtensa, Call0, `--platform=posix --xtensa-soft-mulhigh`. This is the
**last remaining real divergence** in that differential: 117 match / 3 differ /
20 do not compile of 140, and the other two differing rows are artifacts of
comparing naively to the oracle rather than through their real Makefile recipes.
See `working/bug-a-hosted-xtensa-diverges-from-the-oracle-on-21-cross-programs`.

Repro is one line:
`./compiler/pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh test/test_cross_float.pas <out>`
then `qemu-xtensa <out>` against a native build of the same source.

**Start at the width selection, not the arithmetic** — the digits that ARE
printed are correct, so whatever computes them is fine and whatever decides how
many to print is not.
