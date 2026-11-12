---
track: A
tags: [O]
prio: 30
type: perf
blocked-by: []
summary: "On xtensa, the Ord/Chr/Integer()/LongWord()/Char()/Boolean() passthroughs emitted their argument whole, so `Chr(Ord('0') + d)` was a 64-bit pair add (the sum is typed Int64). A result of at most one word now asks for the argument's low word only (EmitLow32Xtensa), so the binop narrows. This is riscv32's 375d0be9b7, ported. Remote-thermostat S3 .text 511,230 -> 509,206 B, RAM unchanged."
status: done
owner: unassigned
---

# Xtensa: a one-word cast evaluated its argument at 64 bits

This follows
[[perf-a-xtensa-keeps-the-pair-path-where-only-the-low-word-is-kept]],
the same demand applied to one more consumer.

## Checked

- The self-rebuild reaches a fixedpoint.
- test-xtensa gained rows for three programs on windowed and call0 at -O0 and
  -O2, each against the x86-64 oracle. All pass. The two low-32 programs had
  only IDF S3 rows before.
  - test_rv32_one_word_cast_keeps_the_low_word
  - test_rv32_low32_narrowing_keeps_64bit_answers
  - test_rv32_pointer_math_through_int64_is_32_bit
- Thermostat S3 object (build.sh flags): .text 511,230 -> 509,206 B; .data,
  .bss and .rodata unchanged.
