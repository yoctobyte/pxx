---
slug: bug-f-riscv32-sin-loses-about-nine-digits-near-a-zero-so-mathdemo-self-reports-failures
track: F
prio: 20
type: bug
status: open
created: 2026-09-02
found-by: frankC
owner: ""
blocked-by: []
summary: "examples/mathf/mathdemo.pas prints ALL OK on i386, arm32 and aarch64 and FAILURES on riscv32 AND xtensa, on one row of 66: `real = double (sin)` gives -0.000000087 where the others give 0.000000000. The two failing targets produce BYTE-IDENTICAL output, and they are exactly the two SOFT-FLOAT targets — so this is not per-backend codegen but one shared implementation, compiler/builtin/softfloat.pas. Accuracy near a zero, probably argument reduction. One fix helps every soft-float target."
---

# riscv32's `sin` loses about nine digits near a zero

Found by compiling `examples/` across five backends against the x86-64 oracle
(the `umbrella-cross-target-codegen-is-correct` attempt, 2026-09-02).

```
mathdemo | i386:ok arm32:ok riscv32:DIFF aarch64:ok xtensa:ok
```

The whole difference, 4 diff lines out of 66:

```
< ok    real = double (sin) = 0.000000000
> FAIL  real = double (sin) = -0.000000087   want 0.000000000
< ALL OK
> FAILURES
```

**The program grades itself**, which is why this is worth a ticket rather than a
shrug: `mathdemo` prints `FAILURES` on riscv32 and `ALL OK` everywhere else, so
anyone running the examples on riscv32 sees a red program.

## Why this is F and not the cross-target umbrella

The rule is *rank the mechanism, never the datatype*. This is not a
control-flow, ABI or codegen divergence that happens to live in float code — the
value is nearly right and wrong in the last digits, which is the signature of
**accuracy in the soft-float `sin` itself**, most likely argument reduction near
a zero of the function. That is float math, so it is F and low prio by
definition.

If it turns out to be a wrong branch or a truncated operand rather than
accumulated error, **it stops being F** and belongs under the cross-target
umbrella at real priority. Whoever picks it up should establish which it is
first — the two have different owners.

## Repro

```
./compiler/pascal26 examples/mathf/mathdemo.pas /tmp/md_x64          && /tmp/md_x64 > /tmp/md.oracle
./compiler/pascal26 --target=riscv32 --platform=posix examples/mathf/mathdemo.pas /tmp/md_rv
tools/run_target.sh riscv32 /tmp/md_rv | diff /tmp/md.oracle -
```

## Bound

HEAD `7cc404961`, compiler `709ec4626a67`. Only the one row differs; the other
65 lines, including every other float row in the same program, match the oracle
exactly. Not checked against FPC — `tools/fpc_diff_probe.sh` is the instrument
and would say whether x86-64 or riscv32 is the odd one out against a third
opinion, and I did not run it.

## Narrowed the same day — it is not riscv32, it is SOFTFLOAT

Once xtensa could build sysutils (`7cc404961`), `mathdemo` built for it too and
produced **byte-identical output to riscv32** — the same single row, the same
`-0.000000087`, the same `FAILURES`.

```
mathdemo | i386:ok arm32:ok riscv32:DIFF aarch64:ok xtensa:DIFF
           (riscv32 and xtensa outputs: cmp says IDENTICAL)
```

That is the discriminator. **riscv32 and xtensa are the two SOFT-FLOAT targets**;
i386 (x87), arm32 and aarch64 (hardware FP) are all correct. Two independent
backends producing the same wrong bits to the last digit is not two codegen
bugs — it is **one implementation they share**, `compiler/builtin/softfloat.pas`.

So the ticket is: `sin` in softfloat.pas loses ~9 digits near a zero, and any
soft-float target shows it. The slug says riscv32 because that is where it was
first seen; the subject is softfloat.

This also means the fix is **one file and helps every soft-float target at
once**, which is worth more than the prio suggests — and that a per-backend
investigation would have been the wrong shape entirely.

Still F: the mechanism is accuracy in a float routine. Still worth checking
against FPC before assuming ours is the wrong one.
