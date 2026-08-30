---
track: A
type: bug
prio: 50
status: open
found: 2026-08-30
found-by: frankS
---

# `IR_RTTI_REG` and `IR_RESOURCES` have no riscv32 arm — anything that USES typinfo fails to compile

```
$ ./compiler/pascal26 --target=riscv32 test/test_class_of.pas /tmp/x
pascal26:664: error: target riscv32: unsupported node in IR codegen: rtti_reg
  in: ./compiler/../lib/rtl/typinfo.pas
```

x86-64 emits the `-100` / `-101` data-ref sentinels by hand; aarch64 has
`EmitLoadDataRefA64(0, -100)` and `(0, -101)`. **riscv32 has neither arm**, and
neither did xtensa until 2026-08-30.

The blast radius is wider than "RTTI programs": the failing unit is
`lib/rtl/typinfo.pas` itself, so **any** program that uses typinfo — directly or
through streaming, LFM, or `class of` — cannot be compiled for riscv32.
Six programs in the cross differential are blocked by it on xtensa; the same
six are `# SKIP`ped or absent for riscv32.

## Fix

Two lines, mirroring aarch64:

```pascal
    IR_RTTI_REG:  EmitLoadDataRefRISCV32(reg_a0, -100);
    IR_RESOURCES: EmitLoadDataRefRISCV32(reg_a0, -101);
```

Whoever takes it should **check what surfaces underneath** rather than closing
on the compile: on xtensa these two lines exposed a missing `in` operator, which
exposed a missing `IR_SET_COPY`, which exposed a by-value set parameter passed
as one address word — a silent wrong-answer bug. `typinfo.pas` exercises all
four, so a backend that has never compiled it has never run any of them.

## Why it was filed rather than fixed

Found while porting the arm INTO `ir_codegen_xtensa.inc`. The port went from
**aarch64** precisely because riscv32 — the usual and closest donor — turned out
not to have one, which is only visible if you check that the arm you are copying
from exists. Track S holds `ir_codegen_xtensa.inc`, not
`ir_codegen_riscv32.inc`, so this is filed for whoever holds Track A.

## Bound

Object-level, at `b859f44e51d6`. One compile per program, error text taken
verbatim. Not fixed and not attempted on riscv32; the claim that aarch64 and
x86-64 have the arms is from reading their case labels. Whether riscv32 has the
same `in` / set-family gaps underneath is UNMEASURED — the rtti_reg error stops
the compile before they can surface, which is the point of the note above.
