---
track: A
tags: [O]
prio: 30
type: perf
blocked-by: []
summary: "On xtensa, a store through memory evaluated the value, pushed it, evaluated the address and popped it into a3, even when the value was a small constant. A constant in movi range (-2048..2047) into a 1/2/4-byte non-ragged destination is now loaded after the address, straight into a3, and a field offset rides in the store. This is riscv32's af239c24d7, constant half. Remote-thermostat S3 .text 483,166 -> 481,722 B, RAM unchanged."
status: done
owner: unassigned
---

# Xtensa: a constant stored through memory was spilled around the address

This follows
[[perf-a-xtensa-a-field-offset-is-added-to-the-address-before-the-access]].

## Not ported

riscv32 also loads a frame-local value after the address. Doing that safely
needs a whitelist of addresses that cannot run code which writes the local
(Rv32AddrRunsNothing). That half is left for later. A constant has no such
question: it cannot change, and evaluating it has no effect.

## Checked

- The self-rebuild reaches a fixedpoint.
- Seven programs match the x86-64 oracle on hosted xtensa, windowed and call0,
  at -O0 and -O2: 28 of 28.
  - test_rv32_store_through_a_frame_address gets test-xtensa rows of its own.
  - test_rv32_field_offsets_ride_in_the_access.
  - test_rv32_leaf_operands_skip_the_spill.
  - Two packed-record programs.
  - The two low-32 programs.
- A mutation test confirms the path is covered: storing the constant plus one
  is caught by the frame-address program and by the field-offset program.
- Thermostat S3 object (build.sh flags): .text 483,166 -> 481,722 B; .data,
  .bss and .rodata unchanged.
