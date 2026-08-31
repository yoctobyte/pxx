---
track: A
type: bug
prio: 50
status: done
found: 2026-08-30
found-by: frankS
owner: frank-rust
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

## Resolved — frank-rust, 2026-08-31, fixedpoint `4456e3b467aa`

Two arms in `compiler/ir_codegen_riscv32.inc`, before `IR_SYSCALL:`, mirroring
aarch64 (`ir_codegen_aarch64.inc:4072`) and xtensa (`ir_codegen_xtensa.inc:3451`):
`a0` gets the registry / resource-table address via the `-100` / `-101` data-ref
sentinels the linker fills in.

### What surfaced underneath — the ticket's own instruction, answered by measurement

The ticket warned that on xtensa these two lines exposed a missing `in`, then a
missing `IR_SET_COPY`, then a by-value set parameter passed as one address word.
**That cascade does not repeat on riscv32**, and this is measured, not inferred
from "riscv32 already has `IR_SET_COPY`":

A probe covering `in`, `+`/`-`/`*` on sets, `=` and `<=`, a 256-element byte set,
a `set of Char`, and a by-value set parameter that mutates its own copy runs
**byte-identical** on riscv32 and x86-64. So does `test_class_of` and four of the
five typinfo programs.

### `test_rtti` differs and it is NOT a defect

Two kinds of row differ. The pointer rows differ because the targets load at
different bases — the prop-to-prop stride is 64 on both. `InstanceSize` reads 80
native, 64 riscv32.

The 64 is **the 32-bit layout, measured**: the same class compiled for i386 and
arm32 prints the same nine numbers as riscv32 (`ptr 4 / string 8 / Integer 4 /
TAlign 4 / TAlignSet 32 / TMethod 8 / TObject 4 / TBase 12 / TChild 64`), and
aarch64 prints riscv32's 64-bit twin. `test_rtti` has no `.expected` and asserts
none of this; it is an address-printing program, not a cross-target oracle.

### The residual question, and who owns it

Not-a-defect is half a finding, so: **six IR node kinds are still absent from
riscv32** — `IR_CLONE`, `IR_COSWITCH`, `IR_IMTADDR`, `IR_IO_LOCK`,
`IR_IO_UNLOCK`, `IR_MULHI`. Four cannot be reached (`IR_MULHI` errors at the
emission site for non-64-bit targets; `IR_IO_LOCK`/`UNLOCK` are gated to
x86-64/i386/aarch64/arm32; `IR_IMTADDR` has no emitter at all, and interface
dispatch through a `TInterfacedObject` runs correctly on riscv32 anyway).

**Two are reachable and are filed separately** as
`bug-a-pxxcoswitch-and-pxxclone-are-missing-on-riscv32` — `__pxxcoswitch(@a, @b)`
compiles for arm32 and x86-64 and gives `unsupported node in IR codegen:
coswitch` on riscv32. Compile-time error, not a wrong answer.

*(A methodological note worth keeping: the first pass of that node-coverage diff
reported `IR_WRITELN` missing too. It is present as the trailing label of
`IR_WRITE, IR_WRITELN:` — the grep anchored at line start and answered correctly
about a different question. riscv32 obviously writes lines; that implausibility
is the only reason it got checked.)*

## Log
- 2026-08-31 — resolved, commit 7c788cb8a.
