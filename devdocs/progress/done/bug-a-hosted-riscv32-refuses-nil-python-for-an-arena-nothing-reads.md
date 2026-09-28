---
slug: bug-a-hosted-riscv32-refuses-nil-python-for-an-arena-nothing-reads
track: A
prio: 50
type: bug
status: done
owner: ""
created: 2026-09-28
found-by: frankh-95 (hosted riscv32 and xtensa refuse Nil Python, so a C3 bug needs a board); lifted by frankD
tags: [nilpy, riscv32, esp32c3, cross-target]
blocked-by: []
summary: "Hosted riscv32 Linux refused every Nil Python program ('Nil Python is not supported on hosted riscv32 Linux yet'), because the entry stub would have had to mmap a heap arena and EmitMmapArena has no riscv32 arm. Nothing on riscv32 READS that arena: the only reader of BSS_HEAP_PTR/BSS_HEAP_END is the x86-64 inline allocator, and riscv32 allocates through builtinheap's HeapMmap (generic mmap, 222). The refusal is lifted, as it was for hosted xtensa in 8529eb30e8, and Nil Python runs under qemu-riscv32, so C3 bugs can be looked at without a board."
---

# Hosted riscv32 refuses Nil Python for an arena nothing reads

The refusal was in `EmitProgramEntryForTarget`'s riscv32 arm. It fired when
the Nil Python driver asked for a heap arena on a hosted profile.

## Why lifting it is safe

- Every writer of BSS_HEAP_PTR/BSS_HEAP_END was checked (`grep -rn` over
  compiler/, including the builtin units). The only reader is the x86-64
  inline allocator in symtab.inc.
- builtinheap's `HeapPtr` is a different variable. It is filled by
  `HeapMmap`, whose riscv32 arm is the generic mmap (222). Under
  `qemu-riscv32 -strace` it shows as a successful
  `mmap2(NULL,268435456,...,MAP_PRIVATE|MAP_ANONYMOUS,-1,0)`.
- On xtensa this was measured, not only reasoned: an arena whose mmap failed
  still ran every row. See bug-a-nil-python-does-not-build-for-xtensa-call0.

## Measured (2026-09-28, qemu-riscv32)

The following match their .expected:

- `test_nilpy_sys_maxsize_follows_the_target.npy` against `.expected32`
  (the same file whose row used to assert the refusal);
- `test_nilpy_cross32_values.py`;
- `test_nilpy_attribute_off_a_virtual_call_result.npy`.

The row that asserted the refusal (test-core, next to the --threadsafe
riscv32 guard) now runs that file, with the other two beside it.
