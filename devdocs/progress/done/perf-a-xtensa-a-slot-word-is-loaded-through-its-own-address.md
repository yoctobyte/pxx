---
track: A
tags: [O]
prio: 30
type: perf
blocked-by: []
summary: "On xtensa, IR_LEA of a slot that holds a pointer (a var/out param, a dynamic array, an open-array value param, a managed string read, any slot ABIParamSlotHoldsValueAddr names) formed the slot address with addi off a7 and then loaded through it. That is 5 bytes where one l32i.n/l32i off the biased a7 is 2 or 3. The string-assignment arm did the same for the caller's slot and the old handle. Both now load the word directly when the slot is in reach (windowed); call0 and far slots keep address and load. This is riscv32's 0464cc9378, slot-word part. Remote-thermostat S3 .text 461,315 -> 449,547 B (-2.6%), RAM unchanged."
status: done
owner: unassigned
---

# Xtensa: a slot word was loaded through its own address

This follows
[[perf-a-xtensa-a-repeated-literal-is-emitted-again-in-the-same-body]].

## Census

`addi a2, a7, K ; l32i.n a2, a2, 0` was the most common pair left in the
thermostat object: 1,658 sites, mostly `Self` and var params at offset 60
and 56.

## Fix

- XtLoadFrameWord(rd, off) is one l32i off a7 when XtFrameDirect accepts the
  slot. Otherwise it forms the address and loads through it, as before.
- XtLoadSlotWord(rd, si) does the same for a global or a frame slot.
- IR_LEA uses XtLoadSlotWord in every arm that reads the slot. It forms the
  address only in the final arm, where nothing is loaded.
- The string-assignment arm uses the same helpers for the caller-slot loads
  and the old-handle load.

## Checked

- The self-rebuild reaches a fixedpoint.
- The quick gate is GREEN.
- test-xtensa RC=0 and test-esp-idf RC=0.
- A mutation test confirms the path is covered: loading one word past the
  slot changes the output of the field-offset program and the frame-address
  program.
- Thermostat S3 object (build.sh flags): .text 461,315 -> 449,547 B; .data,
  .bss and .rodata unchanged.
