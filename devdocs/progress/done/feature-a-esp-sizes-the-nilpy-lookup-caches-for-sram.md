---
slug: feature-a-esp-sizes-the-nilpy-lookup-caches-for-sram
track: A
prio: 45
type: feature
status: done
owner: claude-dupwt
created: 2026-11-19
found-by: claude-dupwt, the .bss census (PXXDBG=a.datamap) for feature-a-a-table-filled-at-startup-is-sram-that-could-have-been-flash
tags: [esp, sram, nilpy, ram]
blocked-by: []
summary: "On an ESP NilPy image 49 KB of the 50.7 KB .bss are lookup caches sized for desktop: PyAttrLkSlot 32 KB (8192 slots), PyLkSlot 8 KB (2048), PyDynAttrNameSeen 4 KB, TokCache 1.5 KB, two 1 KB kind caches. All index with `and (N - 1)`, so any power of two is correct. Smaller ESP sizes (needing a PXX_ESP define; only PXX_ESP_BARE exists today) would return tens of KB of SRAM at the cost of more misses on programs with many (class, attribute) pairs. Measure with examples/esp32/nilpy-c3/build.sh sram + qemu-assert (and a hit-rate count) before choosing sizes."
---

# ESP sizes the NilPy lookup caches for SRAM

See the census in feature-a-a-table-filled-at-startup-is-sram-that-could-have-been-flash.

## Done 2026-11-19 (claude-dupwt)

A new predefine, `PXX_ESP_TARGET`, is set on any ESP build (`--platform=esp`
or a bare ESP profile). It is deliberately NOT `PXX_ESP`: builtinheap.pas
defines that name locally to mean bare metal, and defining it globally broke
the IDF build (PXXVarClear not found). Under it:

| table | desktop | ESP |
| --- | --- | --- |
| PyAttrLkSlot (pylib) | 8192 slots, 32 KB | 1024, 4 KB |
| PyLkSlot (pyeval) | 2048, 8 KB | 256, 1 KB |
| PyDynAttrNameSeen (pylib) | 4096 B | 512 B |
| TokCache (pyeval) | 64 entries, 1.5 KB | 16, 384 B |

All are hash-masked caches, so any power of two is correct; a smaller one
only misses more often. The two 1 KB kind caches were left alone.

nilpy-c3 demo on esp32c3 under Espressif QEMU (`build.sh sram` / `qemu-assert`):

- our object's SRAM: 59,208 B to 18,632 B (.bss 50,688 to 10,112)
- free DRAM pool: 279,760 B to 320,336 B (+40,576 B)
- qemu-assert: OK (output == main.expected)

Hosted and non-ESP riscv32 builds keep the desktop sizes (checked with
a.datamap). Not measured: the hit rate on a program with many classes. If
an app slows down on the chip, PY_ATTRLK_SLOTS is the knob.
