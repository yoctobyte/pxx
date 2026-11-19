---
slug: bug-c-xtensa-object-data-puts-a-dead-runtime-string-and-const-arrays-ahead-of-user-data
track: C
prio: 35
type: bug
status: done
created: 2026-11-19
found-by: rd (Rainyday kernel seat), Rainyday tests/xtensa/fixed.c built with pxx
tags: [cfront, xtensa, emit-obj, data-layout, rodata, rainyday]
blocked-by: []
summary: "A freestanding xtensa object (--target=esp32s3 --freestanding --emit-obj) starts its .data with 0x1c bytes nothing references: a pxx string literal \"-\\n\" with its 24-byte header. And `static const char greeting[] = \"...\"` goes to .data, where gcc puts it in .rodata (flash). Both push the user's first variable off the start of .data. Rainyday's tests/xtensa/fixed.c checks that `int counter` is at 0x3D400000 (prog-fixed.ld) and fails with the pxx build, where it is at 0x3d40003c."
---

## Repro

    int counter = 100;
    void _start(void) { for (;;); }

`pascal26 --target=esp32s3 --freestanding --emit-obj d1.c d1.o`:
`.data` is 0x20 bytes; `counter` is at 0x1c. Bytes 0..0x17 are zero, then
`2d 0a 00 00` ("-\n"). No relocation in the object refers to `.data`, so
the string is dead: ObjRoDropDeadStrings does not reach it, or it is kept
in the RW half.

In fixed.c, `static const char greeting[] = "fixed: constant from flash\n";`
also lands in `.data` (offset 0x20), not `.rodata`. gcc: `.rodata`. That
costs RAM on the ESP32 as well as moving `counter`.

## Fix

1. Find which runtime piece emits "-\n" in a freestanding C object, and
   drop it when nothing references it (or keep it in `.rodata`).
2. A const-qualified file-scope array with a constant initialiser goes to
   `.rodata`, as gcc does (check the Pascal typed-const path, which already
   moves typed consts to flash: ObjRoAdoptDeadTypedConsts).

Done when fixed.c, built with pxx and run as
`FIXED=1 tools/esp32-exec.sh init=<it> init2=<it>` in Rainyday, passes.

## Done 2026-11-19 (rd)

Three pieces, ESP objects (xtensa/riscv32 --emit-obj --platform=esp) only:
1. The fixed low block is reserved as 32 bytes there (DataResvLen), and
   ObjRoDropDeadStrings drops it as a writable dropped piece when no
   reference reaches it (DataResvDrop; RoLayoutPrepare). 32, so what
   follows keeps its residue mod 16.
2. A C object whose own type is const (SymCConstObj: a const base, no
   star in its declarator, not a pointer) goes to .rodata referenced or not
   (ObjRoAdoptDeadTypedConsts), unless a self-relative word touches it. Its
   trailing zero padding up to the next data symbol goes with it
   (ConstObjPaddedEnd). `const char *names[]` stays writable.
3. A writable piece made only of data symbols and short zero padding keeps
   its offset modulo the largest alignment those symbols can need
   (RwPieceModulus: a power of two dividing the offset and, for a C global,
   the size), not modulo 16. Otherwise `counter` kept the hole the moved
   array left.

Measured: test/c_esp_obj_data_layout.c, `counter` at .data+0 and .data
0x10 on esp32s3 and esp32c3 (were 0x38 and 0x48). gcc: .data 0xc, the
const array in .rodata. Rainyday tests/xtensa/fixed.c built with pxx:
`fixed: ok` on the esp32s3 kernel; abi32, mmap, alloca, vfork, romfile,
signal and selfexe still pass. All ten now pass with pxx.

