---
track: ESP
tags: [esp, xtensa, riscv32, emit-obj, iram, gibux]
prio: 5
type: bug
blocked-by: []
summary: "The ESP object writer packed the IRAM function bodies end to end in .iram1.text. A body following one of odd length started off the word, and its inline L32R literal pools, laid out for its 4-aligned Code[] address, were read from the wrong word. Gibux's caches_init sat at .iram1.text+0x77, loaded 0x81000000 as its frame size, and the first store faulted (QEMU exception 10, then a double exception). Each body is now placed congruent mod 4 to its Code[] address, with padding between bodies, which also keeps CALLn targets word-aligned."
status: done
owner: unassigned
---

# IRAM bodies packed off their literal alignment

Reported by the Gibux kernel session on its first boot attempt of the pxx-built ESP32-S3 kernel (latest-5c3269f5f6).

## Cause
writeELF32RelIram assigned `ObjProcIramOff[i] := iramSize` and added each body's length. Code[] function starts are word-aligned, and both the L32R offsets and the pool padding were computed there. L32R ignores the low two bits of the address, so once a body moved by 1–3 bytes, every literal it read was a misaligned mix of two words.

This has been latent since the IRAM writer existed. Pascal `iram;` programs had mostly 4-multiple bodies, or a single IRAM routine.

## Fix
The offset is padded until it is congruent mod 4 to `Procs[i].BodyAddr`. Both writer loops (FPC and pxx) write the gap.

## Test
tools/check_esp_section_attr.py asserts that every function in .text and .iram1.text is word-aligned. The old compiler fails it: xtensa_start at .iram1.text+0x47.
