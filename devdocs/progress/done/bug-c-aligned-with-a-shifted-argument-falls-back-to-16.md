---
title: "C: __attribute__((aligned(1 << N))) fell back to 16 instead of 2^N"
status: done
owner: claude-dupwt
prio: 70
area: cfront
---

The aligned() evaluator (CAttrAlignExprAt, compiler/clexer.inc) read
literals, sizeof/_Alignof of a scalar type, parentheses and products. It did
not read `<<`, so it warned "cannot evaluate the argument" and used the
biggest alignment (16). FreeBSD's and Linux's CACHE_LINE_SIZE is
`(1 << CACHE_LINE_SHIFT)`, so every `__aligned(CACHE_LINE_SIZE)` struct in the
DRM core and LinuxKPI (64 under gcc) got a different size and member offsets
from gcc. That is a silent ABI break against any gcc-built object. Found in
the GPU-driver census (feature-nodisx-linux-gpu-drivers-built-by-pxx), where
the warning appeared in every drm file.

Fix: a left-shift level above the product (`Term { << Term }`). The shift
count is bounded to 0..30, and anything else still takes the warned
fallback. Test row c_alshiq26 (test/c_aligned_shift_and_asm_iq.c), whose
expected output is gcc's.
