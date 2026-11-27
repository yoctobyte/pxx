---
title: "C: __builtin_add/sub/mul_overflow"
status: done
owner: claude-dupwt
prio: 75
area: cfront
---

gcc's type-generic checked arithmetic: `__builtin_mul_overflow(a, b, &r)`
stores the result wrapped to r's type and is true when the exact result does
not fit. drm-kmod's include/linux/overflow.h (check_mul_overflow, array_size,
struct_size, size_mul) is built on it, and it was the first error in 1260 of
the 2100 GPU-driver compiles in the third census
(feature-nodisx-linux-gpu-drivers-built-by-pxx).

Fix (compiler/cpreproc.inc, CPDefineOverflowBuiltins): predefined function-like
macros for add/sub/mul, plus the typed spellings (u/s, with no suffix, l and ll),
as a statement expression over __int128. The exact result of two operands of up
to 64 bits always fits 128 bits, with one exception: an unsigned 64x64
product of 2^127 or more wraps. That wrapped value differs from every 64-bit
truncation, so the call still reports overflow, which is right, because such a
product fits no 64-bit type. The operands and the pointer are each evaluated
once.

Test row c_ovfarith26 (test/c_builtin_overflow_arithmetic.c): wrap, sign
change, narrow destinations, the typed forms, single evaluation, and use as a
condition. Its expected output is gcc's.
