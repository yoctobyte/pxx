---
slug: feature-xtensa-builtin-return-address
track: X
prio: 50
type: feature
status: done
created: 2026-11-22
closed: 2026-11-22
found-by: claude-pxx (building Rainyday's esp32s3 profile with pxx: mm/kmalloc.c)
tags: [xtensa, nilix, frame-intrinsics]
summary: "__builtin_return_address(0) (and Pascal's get_pc_addr, the same AN_PCADDR node) errored on xtensa: the frame intrinsics are refused there because register windows have no frame chain. Since Rainyday's 2026-11-20 kmalloc poisoning, which tags each block with its caller, the pxx-built ESP32-S3 kernel did not compile. Now lowered as gcc does on the windowed ABI: a0's low 30 bits with the PC's top two (new IR_RETADDR). The kernel builds and boots in Espressif's QEMU. call0 still refuses."
---

# __builtin_return_address(0) on xtensa

## Found by

`make PROFILE=esp32s3` in a scratch copy of Rainyday (HEAD of 2026-11-22),
with pxx at 6fe477817f:

    mm/kmalloc.c:201: error: get_pc_addr: the stack-frame intrinsics need a
    linked frame-pointer chain, and xtensa's register windows have none

kmalloc.c calls `poison_fill(p, n, __builtin_return_address(0))`. That
landed in Rainyday on 2026-11-20 (e2fbfde, 6a60c67). Rainyday's ticket 0004
still describes an older state ("9 of 60 compile"). Those gaps, g20 and the
IDF runtime in freestanding objects, were closed in pxx on 11-17 and 11-20.

## Fix

Level 0 needs no frame chain. Under the windowed ABI, a0 holds the return
address through the whole body, because pxx's own call0 anchors
(EmitXtensaLongCallSlot) save and restore it. Its top two bits are the
caller's window increment, so gcc's lowering takes a0's low 30 bits and
the current PC's top two. IR_RETADDR (defs.inc 77) does exactly that. The
PC comes from a call0 to the next 4-aligned offset, with a0 kept in a9.
Under call0, a0 is not kept through the body, so the error stays and now
names the ABI.

## Tests

- test_get_pc_addr_xtensa_windowed: hosted windowed xtensa under QEMU. Two
  call sites differ and ascend, the value is stable across calls in the
  body, and the top bits match; same output as pxx x86-64. Hosted C on
  xtensa runs call0 only, so the run-time row is Pascal, which lowers to the
  same node.
- A call0 row checks the refusal.
- c_return_address_esp32s3_object: Rainyday's shape compiled with
  `--target=esp32s3 --emit-obj --freestanding`.
- Rainyday esp32s3, scratch copy: all units compile, rainyday.elf links,
  and in Espressif's QEMU (tools/esp32run.sh) it prints "Hello from the
  Rainyday Kernel.", finds PSRAM, has 4280 KiB free, and halts at "no
  initramfs", as it should without one.
