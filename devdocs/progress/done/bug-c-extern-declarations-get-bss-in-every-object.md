---
track: ESP
tags: [C, esp, xtensa, riscv32, emit-obj, ram, gibux]
prio: 10
type: bug
blocked-by: []
summary: "In an ESP object (xtensa or riscv32 --emit-obj), every extern C declaration got .bss storage nothing used. Every reference already relocated against the UND symbol, but the slot reserved at parse time stayed. Gibux's 61 ESP32-S3 objects carried 1.9 MB of .bss against gcc's 120 KB, so the link failed with DRAM overlapping the bootloader. The ESP writers now cut the import ranges out of .bss in 16-byte granules (ObjBssPlan/ObjBssOff). Each object's runtime signal tables (544 B) are also no longer reserved where no signal runtime exists. An empty freestanding object's .bss went from 584 B to 40 B."
status: done
owner: unassigned
---

# Extern declarations got .bss in every object

## Cause
A C global gets its slot when it is declared. Whether it is an import (every declaration said `extern`, none defined it) is known only after the whole unit is parsed, in ObjDataIsImport. At that point its references are written against the UND symbol, but the slot remained, in every object whose header declared it. `extern struct proc procs[64]` cost 4 KB per object.

## Fix
ObjBssPlan (elfwriter.inc) collects the import ranges. Both ESP writers then shift every live .bss offset down by the cut bytes below it: the GlobFix relocations, the C initialiser relocations (CDR), the data symbols and the section size. Cuts are whole 16-byte granules, so every shift is a multiple of 16 and alignment survives.

## The baseline
EnsureSignalBss (ir_codegen.inc) allocated the 512 B handler table and the 32 B scratch area unconditionally. Only the signal runtime emitters read them, and those run only under TargetHasSignalRuntime, which is false on every ESP build. The tables are now allocated only when that predicate holds. The four parked signal fields stay, because the signal-info builtins read them on every target.

## Test
tools/check_xtensa_freestanding_struct.py:
- It links test/c_xtensa_extern_bss_a.c, whose live globals are interleaved with extern ones and referenced from code and from pointer initialisers, with test/c_xtensa_extern_bss_b.c, which holds the definitions and guard words.
- It runs the result under qemu-xtensa and expects gcc's value, 189.
- It asserts that the declaring object's .bss is under 256 B. The old compiler gives 5740 B.

## Not done
The hosted --emit-obj writers (x86-64 and others) still reserve the slots. They are only wasted space on a host, so they are left alone for now.
