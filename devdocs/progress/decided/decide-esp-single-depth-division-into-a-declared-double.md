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


## DECIDED 2026-08-11 (user): option 2 — the REQUESTED TARGET TYPE decides

> "on #2. the requested target type decides." — user

So when a float-producing operator has **no float operand to take a depth from**
— the ordinal/ordinal case, `1 / 3` — the depth comes from the type the program
actually asked for: the assignment target. `x: Double` gets a double divide;
`x: Single` gets a single one. Nothing changes when an operand IS a float: two
Singles still make a Single on ESP, which is the cheap path the design chose and
the one most MCU code is written in.

That keeps the engineering intent (no silent soft-double tax on code that never
asked for a Double) while removing the failure it caused: a declared `Double`
quietly holding 7 significant digits, and the same source giving different
numbers on ESP than on every other target.

x86-64 / i386 / arm32 / aarch64 are unaffected under any option — their
`FloatBinopResultTk` already answers tyDouble for every float-producing binop.

## Implemented 2026-08-11

`IRWidenOrdinalFloatBinop`, called from the assign lowering where the target
type is known: a float-producing binop whose operands supply no depth is
re-typed to the target's float kind. Both soft-float backends then honour the
node's result type as well as its operands.

Two ordering traps, both found by testing the nested shapes rather than the
reported one:

- **Look inside even when the node needs nothing.** `1/3 + 0.5` assigned to a
  Double: the outer `+` already has a Double operand, but the inner `/` has
  none and is exactly the case the target decides. Stopping at the outer node
  left the division single and the sum inherited it.
- **Recurse BEFORE deciding about the node.** `(1/3) * (1/3)` has two float
  operands, so a node-first rule refused to widen the product and then widened
  both divisions under it — operands Double, product Single, and storing that
  into a Double slot read **0.0**.

The ESP design is preserved where it was the point: a genuinely narrower float
operand still blocks the widen, so `s1 / s2` (two Singles) assigned to a Double
stays a single divide on xtensa/riscv32. That row therefore still differs from
x86-64, where Single is storage-only — deliberate, and not part of this change.

Verified: `test/test_esp_float_depth_from_target.pas` reads identically on
x86-64, i386, arm32, aarch64 and riscv32, with a Single target and an
already-float expression as the controls. `gate.sh quick` GREEN (self-host
byte-identical).
