---
track: ESP
tags: [rtl, heap, xtensa, gibux, nommu]
prio: 20
type: feature
blocked-by: []
summary: "On hosted xtensa (Gibux on the ESP32-S3, no MMU) the pxx heap maps 64 KiB arenas instead of 256 MiB, and a request over half an arena gets its own mapping, so it doesn't abandon the current arena's tail. Before, each process asked for 256 MiB and halved until mmap2 succeeded. Without an MMU that is real memory, 1-2 MiB of PSRAM per process, so a shell plus a three-stage pipeline would exhaust the board's 8 MiB."
status: done
owner: unassigned
---

# The xtensa heap grows in small arenas on a no-MMU kernel

The Gibux kernel session asked for this.

## Change
- builtinheap.pas: HEAP_ARENA gets a CPU_XTENSA arm of 64 KiB. ESP builds (PXX_ESP) keep their own static arena, and other hosted targets keep 256 MiB.
- PXXAlloc: on hosted xtensa, a block needing more than HEAP_ARENA/2 is mapped on its own. It is an ordinary sized block, so free puts it on the big free list and it is reused from there.

Not done: asking /proc/meminfo, or returning memory to the kernel. Freed blocks stay with the process, as on every target.

## Test
tools/check_xtensa_heap_arenas.py runs test/c_xtensa_heap_arenas.c under `qemu-xtensa -strace`. The program makes 200 small allocations, 6 of about 200 KB (freed), and 3 of 150 KB (reusing them). It requires:
- gcc's output
- no mapping over 256 KiB
- exactly one 64 KiB arena

The old runtime maps 268435456 bytes.
