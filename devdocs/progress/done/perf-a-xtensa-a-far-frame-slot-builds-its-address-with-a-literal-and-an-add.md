---
track: A
tags: [O]
prio: 30
type: perf
blocked-by: []
summary: "On windowed xtensa, a frame slot more than 128 bytes below the biased a7 was reached with movi a8, adj; add.n a8, a7, a8 and an access at 0: 7 bytes for a word. It is now addmi a8, a7, H (H a multiple of 256) with the remainder, 0..255, in the access immediate: 5 or 6 bytes. This applies to scalar loads and stores, 64-bit loads and stores, by-ref param slots and the slot-word loads. New encoder xtensa_addmi, checked against xtensa-esp32s3-elf-as. Remote-thermostat S3 .text 449,547 -> 443,199 B (-1.4%), RAM unchanged."
status: done
owner: unassigned
---

# Xtensa: a far frame slot built its address with a literal and an add

This follows
[[perf-a-xtensa-a-slot-word-is-loaded-through-its-own-address]].

## Census

The windowed frame pointer a7 sits XT_FP_BIAS (64) bytes below the frame
base, so the nearest 64 bytes of locals are one l32i.n off a7. A slot further
down has a negative distance from a7, and l32i takes only non-negative
offsets.

- Between -128 and -1 from a7, the access is addi plus an access at 0:
  5 bytes. That is already the shortest form, and it stays.
- Below -128, the access was movi plus add.n plus the access: 7 bytes. The
  thermostat object had 2,752 of these.

## Fix

XtFrameFar(off, sz, rd, adj) emits `addmi rd, a7, H` and returns the
remainder for the access immediate. It applies only when:

- the ABI is windowed;
- the distance from a7 is below -128 and at least -32768;
- the remainder keeps the access aligned.

When those do not hold, it emits nothing and the generic path runs.

Users:

- EmitLoadVarXtensa and EmitStoreVarXtensa, for values and for by-ref
  param slots;
- EmitLoadVar64Xtensa and EmitStoreVar64Xtensa;
- XtLoadFrameWord.

ADDMI is `82 d7 ff` for `addmi a8, a7, -256` and `92 df 02` for
`addmi a9, a15, 512`. The xtensa_addmi encoder refuses an immediate that is
not a multiple of 256 or is out of range.

## Checked

- The self-rebuild reaches a fixedpoint.
- test_xt_far_frame_slots_read_and_write_at_every_width matches the x86-64
  oracle on hosted xtensa, windowed and call0, at -O0 and -O2. It covers byte,
  signed byte, word, signed word, longint, Int64, pointer, string and char
  locals placed past three 400-byte blocks. The windowed -O2 build has 55
  `addmi a8, a7` sites.
- A mutation test confirms the path is covered: a remainder off by 4 breaks
  the string and Int64 rows.
- test-xtensa: RC=0. test-esp-idf: RC=0 on the third run (2026-11-13). The
  two runs before it each stopped on the known C3 (riscv32) interrupt-WDT
  QEMU flake, once at "WriteLn + task end" and once in a boot loop at
  "class slots -dUSE_CLASS"; this diff touches only xtensa files.
- Thermostat S3 object (build.sh flags): .text 449,547 -> 443,199 B; .data,
  .bss and .rodata unchanged.

## Not covered

A by-ref param slot is never far in practice, because params are spilled at
the top of the frame. That arm exists for symmetry with the direct path, and
no test reaches it.
