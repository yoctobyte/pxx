---
track: U
prio: 45
type: decision
blocked-by: []
---

# Decide: on ESP targets, should `x: Double; x := 1/3` compute at SINGLE depth?

- **Type:** decision (Track U) — semantics on xtensa / riscv32 only.
- **Raised:** 2026-08-11. Opened as a bug
  (`bug-a-riscv32-folds-a-double-literal-division-to-single-precision`) and
  withdrawn on measurement: the behaviour is DELIBERATE and documented in the
  code. What is left is a judgement call, so it belongs here.

```pascal
var a, b, x: Double;
begin
  a := 1; b := 3;
  x := a / b;   { every target: 0.33333333333333331483 }
  x := 1 / 3;   { xtensa/riscv32: 0.33333334326744079590 — float32's 1/3 }
end.
```

## Why it happens — by design, not by accident

`FloatBinopResultTk` (`parser.inc`) says so in its own comment:

> On ESP (xtensa/riscv) Single is first-class: single op single -> single, only
> an explicit Double operand pulls the result to soft-Double. **Ordinal operands
> count as "not Double" so int/int under '/' yields the native depth (Single on
> ESP).**

That is a real engineering choice — soft-double on a microcontroller is
expensive, and a target with no FPU should not pay for it silently.

## The fork

The choice is defensible for `s1 / s2` where both operands are Singles. The
question is the ORDINAL case, where there is no float operand to take a depth
from and the only type the programmer actually wrote is the DESTINATION's:

1. **Keep it** (status quo): int/int is Single on ESP. Cheap; matches "native
   depth". Cost: a declared `Double` silently holds a Single's value, and the
   same source gives different numbers on ESP than on every other target — the
   kind of divergence that is very hard to see, since it only shows past the 7th
   significant digit. It was invisible until `write(v:w:d)` became exact enough
   to print those digits (2026-08-11).
2. **Take the depth from the assignment target when there is no float operand.**
   `x: Double` → double division; `x: Single` → single. Costs a soft-double
   divide only where the program asked for a Double.
3. **Ordinal/ordinal `/` is always Double, as elsewhere.** Simplest rule, most
   FPC-like, most expensive on ESP.

**Recommendation: 2.** It keeps the cheap path for genuinely single-precision
code (which on an MCU is most of it) and stops a declared Double from quietly
holding 7 digits. If 2 is too fiddly, 1 is defensible — but then it is worth a
line in the ESP docs, because nothing tells the programmer today.

## Notes for whoever implements the choice

- Only `FloatBinopResultTk`'s ESP branch decides this; both soft-float backends
  then follow the node's result type, so no backend change is needed for 3, and
  2 needs the assignment context threaded into the typing site.
- x86-64 / i386 / arm32 / aarch64 are unaffected under every option.
- The measurement boundary: `1/3` and `2/3` diverge; `1/4`, `10/4`, `0.1`,
  `1.0/3`, `1/3.0` and `a/b` all agree, because they are either exact in float32
  or already have a float operand.
