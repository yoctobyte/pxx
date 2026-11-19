---
slug: feature-a-esp-sizes-the-nilpy-lookup-caches-for-sram
track: A
prio: 45
type: feature
status: backlog
created: 2026-11-19
found-by: claude-dupwt, the .bss census (PXXDBG=a.datamap) for feature-a-a-table-filled-at-startup-is-sram-that-could-have-been-flash
tags: [esp, sram, nilpy, ram]
blocked-by: []
summary: "On an ESP NilPy image 49 KB of the 50.7 KB .bss are lookup caches sized for desktop: PyAttrLkSlot 32 KB (8192 slots), PyLkSlot 8 KB (2048), PyDynAttrNameSeen 4 KB, TokCache 1.5 KB, two 1 KB kind caches. All index with `and (N - 1)`, so any power of two is correct. Smaller ESP sizes (needing a PXX_ESP define; only PXX_ESP_BARE exists today) would return tens of KB of SRAM at the cost of more misses on programs with many (class, attribute) pairs. Measure with examples/esp32/nilpy-c3/build.sh sram + qemu-assert (and a hit-rate count) before choosing sizes."
---

# ESP sizes the NilPy lookup caches for SRAM

See the census in feature-a-a-table-filled-at-startup-is-sram-that-could-have-been-flash.
