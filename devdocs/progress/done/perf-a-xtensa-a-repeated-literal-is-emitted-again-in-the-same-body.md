---
track: A
tags: [O]
prio: 30
type: perf
blocked-by: []
summary: "On xtensa every constant outside movi range, every data reference and every global address was a fresh inline literal: a jump over padding and a 4-byte word, then an L32R. A body that loaded the same value twice paid that each time. At -O2, EmitLoadConstXtensa, EmitLoadDataRefXtensa and EmitLoadGlobAddrXtensa now remember the literals they emitted in the current body pass, and a repeat is one L32R back to the first one. Remote-thermostat S3 .text 481,722 -> 461,315 B (-4.2%), RAM unchanged."
status: done
owner: unassigned
---

# Xtensa: a repeated literal was emitted again in the same body

This follows
[[perf-a-xtensa-a-constant-stored-through-memory-is-spilled-around-the-address]].

## Census

The thermostat S3 object had 5,188 L32R instructions, each behind its own
`j` over an inline literal. Counting literals whose value (or relocation
target) already appeared earlier in the same function gave 1,305 repeats:
1,124 relocated, 181 plain values.

## Fix

- Reuse is keyed by kind (constant, data reference, global address) and
  value. The table holds up to 256 entries per body; when it is full, new
  literals are simply not recorded.
- Scope is one relaxation attempt of IREmitMachineCodeXtensa. The table is
  cleared at the start of each attempt and switched off on exit. So a
  rewound attempt, a nested body, a prologue or epilogue, and another body
  never see a stale position. DCE removes whole bodies, a multiple of 4
  bytes, so the offsets inside one body survive it.
- Inside XtensaWideBegin/End no reuse happens: that code counts bytes, and a
  reused load is 3 bytes where a fresh one is 7 to 10.
- An L32R reaches 256 KiB back from the aligned pc; past that a fresh
  literal is emitted.
- Literals patched after emission (the frame size, the call0 alloca reserve,
  label deltas, LabelFixupAnchor) are emitted directly, not through the three
  helpers, so they are never shared.
- -O0 is unchanged.

## Checked

- The self-rebuild reaches a fixedpoint.
- The quick gate is GREEN.
- test-xtensa and test-esp-idf both return RC=0.
  - One test-xtensa row went red as it was meant to: the forward-jump
    relaxation control. Its generated block of 6,000 `s := s + 1` lines shared
    the literal and fell under 128 KiB again. Each line now adds a distinct
    constant, so every line keeps its own fresh literal (192 KiB windowed,
    216 KiB call0).
  - fs-c3 failed once, with its lines printed in a different order, then
    passed twice in isolation. It runs on C3 (riscv32), which this change does
    not touch.
- A mutation test confirms the path is covered: pointing a reused L32R one
  word too far back changes the output of hello, the field-offset program and
  the low-32 program.
- Raising the table from 256 to 4,096 entries gives the same thermostat size,
  so the cap does not bind there.
- Thermostat S3 object (build.sh flags): .text 481,722 -> 461,315 B; .data,
  .bss and .rodata unchanged.
