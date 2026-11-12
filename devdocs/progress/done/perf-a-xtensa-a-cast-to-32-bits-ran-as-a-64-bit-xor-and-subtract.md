---
track: A
tags: [O]
prio: 30
type: perf
blocked-by: []
summary: "On xtensa, a cast to a 32-bit signed type arrives as `(x xor 2^31) - 2^31` and a mask as `x and $FFFFFFFF`. Both were emitted as 64-bit pair operations, though on a 32-bit register each is the value itself. XtSameLow32 now recognises them (any nesting) and emits the operand alone. This is riscv32's 7ec40c30f6, binop half only. Remote-thermostat S3 .text 509,206 -> 499,646 B (-9.6 KB), RAM unchanged: the RTL spells NativeInt(...) everywhere, PXXBlockCopy's loop included."
status: done
owner: unassigned
---

# Xtensa: a cast to 32 bits ran as a 64-bit xor and subtract

This follows
[[perf-a-xtensa-one-word-cast-evaluates-its-argument-at-64-bits]].

## Not ported

riscv32's 7ec40c30f6 also has two other parts, both left for later:

- a constant fold of such casts (Rv32ConstIntValue), which xtensa has no
  twin of;
- stores through a frame address without the push.

## Checked

- The self-rebuild reaches a fixedpoint.
- test_rv32_cast_to_32_bits_is_the_low_word and the three low-32 programs
  match the x86-64 oracle on hosted xtensa, windowed and call0, at -O0 and
  -O2: 16 of 16. The cast program gets test-xtensa rows of its own.
- Thermostat S3 object (build.sh flags): .text 509,206 -> 499,646 B; .data,
  .bss and .rodata unchanged.
