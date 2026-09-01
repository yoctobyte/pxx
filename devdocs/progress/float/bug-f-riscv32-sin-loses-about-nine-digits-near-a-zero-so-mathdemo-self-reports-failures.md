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
summary: "examples/mathf/mathdemo.pas prints ALL OK on x86-64, i386, arm32 and aarch64 and FAILURES on riscv32, on one row: `real = double (sin)` comes back -0.000000087 where every other target gives 0.000000000. One row of 66; everything else matches byte for byte. Accuracy in the soft-float sin, almost certainly argument reduction near a zero — the mechanism is float math, which is what makes this F rather than a cross-target correctness bug."
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
