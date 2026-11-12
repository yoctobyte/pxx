---
track: A
tags: [O]
prio: 30
type: perf
blocked-by: []
summary: "On xtensa, a load or store through a record field at a constant offset added the offset to the base first: a constant load and an add, or an addi. It then accessed at offset 0. The offset now rides in the l8ui/l16ui/l16si/l32i and s8i/s16i/s32i immediate when it fits the access (byte 0..255, halfword even 0..510, word aligned 0..1020, and a 64-bit pair with both words in reach). Ragged (packed, misaligned) fields are never folded. This is riscv32's 0464cc9378, load/store part. Remote-thermostat S3 .text 487,726 -> 483,166 B (-4.6 KB), RAM unchanged."
status: done
owner: unassigned
---

# Xtensa: a field offset was added to the address before the access

This follows
[[perf-a-xtensa-a-local-index-spills-the-base-and-scales-with-adds]].

## Fix

XtFieldOffFits(addrNode, sz, off) accepts an IR_FIELD with the ragged bit
clear and an offset that fits the access. IR_LOAD_MEM then emits the field's
base and loads at the offset. For a 64-bit pair it loads the high word first,
as before. The generic narrow arm of IR_STORE_MEM does the same: value pushed,
field base, pop, store at the offset. Base alignment is unchanged, since
base + off is the same address either way.

## Checked

- The self-rebuild reaches a fixedpoint.
- test_rv32_field_offsets_ride_in_the_access covers every width, signed and
  unsigned, through var params, pointers, a class and globals, plus offsets
  at and past the immediate range. It and the five other low-32/index
  programs match the x86-64 oracle on hosted xtensa, windowed and call0, at
  -O0 and -O2: 24 of 24.
- A mutation test confirms the fold is covered: a folded load that ignores
  its offset breaks the field program's first row.
- Packed records are unaffected. Each of these matches the oracle on both
  ABIs at both levels:
  - test_a_packed_record_field_reads_and_writes_at_any_offset;
  - test_packed_array_field_in_a_record_and_a_class.
- test_p_unaligned_is_a_transparent_lvalue bus-errors on xtensa, but it did
  so before this change too. It is recorded as
  backlog-esp/bug-a-unaligned-dereference-bus-errors-on-xtensa.
- Thermostat S3 object (build.sh flags): .text 487,726 -> 483,166 B; .data,
  .bss and .rodata unchanged.
