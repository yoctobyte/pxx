---
track: A
tags: [O]
prio: 30
type: perf
blocked-by: []
summary: "On xtensa, every non-constant array index spilled the base, and a 2/4/8-byte element was scaled with one to three adds and then a fourth add for the base. The scale and the base add are now one ADDX2/ADDX4/ADDX8, a new encoder whose bytes were checked against xtensa-esp32s3-elf-as. A 4-byte frame-local index (windowed, in l32i reach) also loads straight into a3 after the base, with no spill. This is the local-index part of riscv32's af239c24d7. Remote-thermostat S3 .text 493,274 -> 487,726 B (-5.5 KB), RAM unchanged."
status: done
owner: unassigned
---

# Xtensa: a local index spilled the base and scaled with adds

This follows
[[perf-a-xtensa-a-constant-index-spills-the-base-and-scales-at-run-time]].

## Fix

- `xtensa_addx(scale, r, s, t)` in xtensaenc.inc computes `ar := (as shl k) + at`.
  It has the same RRR layout as ADD, with op2 = 9/A/B. The bytes were checked
  with the ESP-IDF toolchain's assembler:
  `addx2 a2,a3,a2` = 20 23 90, `addx4` = 20 23 a0, `addx8` = 20 23 b0.
- General IR_INDEX path: for 2/4/8-byte elements, the index is scaled and the
  popped base added in one `addx`. Other sizes are unchanged (`mull`, then
  `add`).
- Frame-local index: the conditions are
  - the index is a 4-byte integer local or by-value parameter;
  - the ABI is windowed;
  - the slot is within `l32i a3, a7, adj` reach;
  - the lower bound fits movi.

  When they hold, the base stays in a2 and the index loads into a3. Then a
  lower-bound `addi` (or `movi a4` + `sub`) and one `add`/`addx`/`mull`+`add`.
  The base is still evaluated first, as before.

## Checked

- The self-rebuild reaches a fixedpoint.
- Six programs match the x86-64 oracle on hosted xtensa, windowed and call0,
  at -O0 and -O2: 24 of 24.
  - test_rv32_leaf_operands_skip_the_spill, which has local indexes over odd
    lower bounds and element sizes 3 and 12.
  - test_rv32_field_offsets_ride_in_the_access, which gets test-xtensa rows
    of its own.
  - The four earlier low-32 and cast programs.
- A mutation test confirms the local path is covered: swapping the addx
  operands in it breaks the leaf program's output from row 4 on.
- Thermostat S3 object (build.sh flags): .text 493,274 -> 487,726 B; .data,
  .bss and .rodata unchanged.
