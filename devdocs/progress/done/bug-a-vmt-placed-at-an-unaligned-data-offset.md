---
track: ESP
tags: [codegen, data-layout, vmt, alignment, xtensa, gibux]
prio: 20
type: bug
blocked-by: []
summary: "A class VMT (and its RTTI and layout backlink words, VMT-8 and VMT-16) was placed at whatever DataLen happened to be. TObject's sat at Data offset 42 on every target, so its slots were pointers at 2-mod-4 addresses. x86 hides it, but the ESP32-S3 faults on an unaligned l32i, and Gibux's loader refuses an unaligned R_XTENSA_RELATIVE (ENOEXEC on the first pxx PIE). All three VMT placement sites (Pascal root class, declared classes, NilPy classes) now pad DataLen to 8 first."
status: done
owner: unassigned
---

# A VMT placed at an unaligned data offset

The Gibux kernel session found it. Exec of the first pxx-built PIE refused hello.o's `.data+0x2a: R_XTENSA_32 .text+0x7750` (`__pxxTObjectDestroy`), a 4-byte pointer at a 2-byte offset.

## Cause
A temporary trace in AddMethodFix fired on the compiler's own x86-64 self-host: MFK_VMT at pos 42. The VMT placement sites in pasparser_prog.inc (the TObject root), pasparser_decl.inc (declared classes) and pyparser.inc (NilPy) all start the 16-byte backlink block at the current DataLen, with no alignment.

## Effect
On ESP the unaligned slots are .rodata+0x12 and +0x1a (with the read-only split) in every Pascal class program. They were not loaded often enough to show up, because they are the root's padding slot and backlinks. In a Gibux PIE the loader rejects the image outright.

## Fix
Pad DataLen to 8 before each VMT block. Self-hosting is still byte-identical.

## Test
tools/check_xtensa_pie_link.py now requires every R_XTENSA_32 in a data section to sit at a multiple of 4, for the PIE hello (--no-ro-data) and for test/esp_obj_class_slots_need_a_class.pas (esp32s3, read-only split). The old compiler has 1 unaligned pointer and 2 respectively.
