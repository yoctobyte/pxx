---
summary: "RESOLVED 2026-11-25: PyAttrLkIndex, the hash of NilPy's (class, name, kind) attribute-lookup cache (and of pyeval's PyLkIndex, which uses it), was written for 64-bit words. On a 32-bit target its final `h xor (h shr 32)` zeroed the hash: on riscv32 (the C3) and i386, all 512 keys of a probe went to slot 0, so the 1024-slot cache worked as 4 slots. arm32 kept 110 slots but lost the kind. A CPU32 body now mixes in 32 bits, over the same bytes read as four byte-assembled words: 398 of 512 keys get distinct slots on all three targets (a uniform hash gives ~403)."
type: bug
track: N
prio: 55
status: done
created: 2026-11-25
found-by: a local /code-review of pin v455
owner: claude-dupwt
tags: [nilpy, esp, riscv32, performance, hash]
blocked-by: []
---

## Measured

The probe is the function body copied into a standalone program: 16 classes,
8 names, 4 kinds, 1024 slots.

| target | before | after |
|---|---|---|
| x86-64 | 351 distinct | (unchanged, 64-bit body) |
| riscv32 | 1 | 398 |
| i386 | 1 | 398 |
| arm32 | 110, kind ignored | 398 |

A getattr/hasattr-heavy NilPy loop on qemu-riscv32 went from 5.65-6.04 s to
5.08-5.48 s (3 runs each), about 10%. Statically compiled attribute access does
not use this cache, so ordinary code does not change.

## Fix

compiler/builtin/pylib.pas: `{$ifdef CPU32}` body. It reads the first and last
8 bytes of the name as four words, so `__prop_get_x` and `__prop_set_x` do not
collide. The words are built from single bytes, so there is no misaligned load
on Xtensa. The mixing is murmur3-style, and the kind goes in at bit 28.

## Test

The change affects speed only, so the guard is that nothing breaks with a
working cache. test-riscv32, test-arm32 and test-i386 all ran to the end with 0
failures. The hash is internal and no program can observe it, so there is no
row for its spread; that is measured above.

A side note, not chased: `NativeUInt shr 32` on a 32-bit value gives different
results on arm32 and riscv32/i386, which is why the before column differs.
Pascal leaves a shift by the word width undefined.
