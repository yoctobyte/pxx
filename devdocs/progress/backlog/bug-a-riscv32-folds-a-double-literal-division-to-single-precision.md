---
track: A
prio: 45
type: bug
blocked-by: []
---

# riscv32: a constant-folded Double division comes out SINGLE precision

- **Type:** bug (silent wrong value, one target only) — **Track A**
- **Found:** 2026-08-11 while making `write(v:w:d)` exact
  ([[bug-a-write-fixed-fraction-digits-past-16-are-invented]]) — the new exact
  expansion made it visible by printing the value's real digits.
- **Pre-existing on `pinned`** (controlled).

```pascal
var a, b, x: Double;
begin
  a := 1; b := 3;
  x := a / b;  WriteLn(x:0:20);   { all targets: 0.33333333333333331483  — right }
  x := 1 / 3;  WriteLn(x:0:20);   { riscv32:    0.33333334326744079590  — WRONG }
end.
```

`0.33333334326744079590` is exactly the **float32** value of 1/3 widened to a
double. So the constant FOLD is being done in (or stored through) single
precision; the runtime division on the same target is correct, and x86-64,
i386, arm32 and aarch64 all fold correctly.

## Boundary (measured)

| expression | riscv32 |
| --- | --- |
| `a / b` (both Double vars) | correct |
| `1 / 3` (folded) | **single-precision value** |
| `0.1` (literal) | correct |
| `1.0000000000000002` (17 sig digits) | correct |

So a plain literal survives; it is the folded DIVISION that loses precision.
Start by dumping what the fold emits — likely a float32 constant in the literal
pool, or a `fdiv.s` where the operands are doubles.

## Why it stayed hidden

`write(v:w:d)` used to approximate the fraction past ~16 digits on every
target, so the two answers agreed for as many digits as anyone printed. Making
the fraction exact is what separated them.

## Gate

The four rows above matching x86-64 on riscv32, `tools/fpc_diff_probe.sh` clean
for the float surface, self-host byte-identical.
