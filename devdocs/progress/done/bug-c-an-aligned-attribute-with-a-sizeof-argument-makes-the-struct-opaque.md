---
slug: bug-c-an-aligned-attribute-with-a-sizeof-argument-makes-the-struct-opaque
track: C
prio: 80
type: bug
status: done
created: 2026-11-14
found-by: pixx-f2 (busybox bzip2), diagnosed by claude-opus
tags: [c-frontend, busybox]
blocked-by: []
summary: "`__attribute__((aligned(sizeof(long))))` on a struct member read its argument as digits only, got 0, and an alignment of 0 marks the struct body not simple: the WHOLE struct went opaque, so every member access was a 4-byte load/store at offset 0, with no diagnostic. busybox's bzip2 EState has `Bool inUse[256] ALIGNED(sizeof(long))`, so `crc32_filltable(s->crc32table, 1)` got a truncated sign-extended address and `echo hello | busybox bzip2` crashed (SIGSEGV, no output). The argument is now evaluated: integer literals (hex, suffixes), sizeof/_Alignof/__alignof__ of a scalar type or any pointer, parentheses, and products. Anything else WARNS and takes the target's biggest alignment rather than going opaque."
---

# aligned(sizeof(T)) made the struct opaque

clexer.inc: new `CAttrAlignExprAt`, used by `CAttrAlignedValueOf`.

Found by pixx-f2: busybox 1.36.1 `bzip2` (compress) wrote nothing under pxx while
gzip, gunzip and bunzip2 were fine; standalone bzip2 1.0.8 (no ALIGNED member)
compressed correctly under pxx, which pointed at busybox's own EState.

Test: `test/c_aligned_attribute_sizeof_argument.c`, x86-64 and i386, expected
output = gcc / gcc -m32 (`.i386.expected` holds the ILP32 layout line).
