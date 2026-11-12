---
track: A
tags: [O]
prio: 30
type: perf
blocked-by: []
summary: "On xtensa, IR_INDEX pushed the base, loaded the index, subtracted the lower bound, scaled and popped, even when the index was a constant. A constant index is now a byte offset folded at compile time: one addi, or a constant load and add past the imm8 range. This is the constant-index part of riscv32's af239c24d7. Remote-thermostat S3 .text 499,646 -> 493,274 B (-6.4 KB), RAM unchanged."
status: done
owner: unassigned
---

# Xtensa: a constant index spilled the base and scaled at run time

This follows
[[perf-a-xtensa-a-cast-to-32-bits-ran-as-a-64-bit-xor-and-subtract]].

## Fix

`(index - lo) * elemSize` is computed in the compiler when the index is an
IR_CONST_INT and every factor is small enough that the product fits Int32.
Wider cases keep the general path. The fold runs after the managed-string
COW and deref step, so it adds to the same base.

## Not ported yet (af239c24d7's other parts)

- A frame-local index loaded straight into the second register.
- Store-new-then-release for a managed string stored into a frame local.
- Skipping the push around string compares with no temporaries.
- Stores through memory with a constant or local value.

## Checked

- The self-rebuild reaches a fixedpoint.
- Six programs match the x86-64 oracle on hosted xtensa, windowed and call0,
  at -O0 and -O2: 24 of 24.
  - test_rv32_leaf_operands_skip_the_spill (constant indexes over odd lower
    bounds, element sizes 3 and 12) gets test-xtensa rows of its own.
  - test_rv32_field_offsets_ride_in_the_access.
  - The four earlier low-32 and cast programs.
- A mutation test confirms the fold is covered: dropping `- lo` makes the
  leaf program die with SIGBUS.
- Thermostat S3 object (build.sh flags): .text 499,646 -> 493,274 B; .data,
  .bss and .rodata unchanged.
