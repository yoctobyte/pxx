---
title: "C constant expressions: ilog2(4) as a bitfield width (bit builtins, dead _Generic arm)"
status: done
owner: claude-dupwt
prio: 70
area: cfront
---

FreeBSD's ilog2(n) is `__builtin_constant_p(n) ? (63 - __builtin_clzll(n)) :
_Generic((n), ...)(n)`. i915's intel_display_types.h uses it as a bitfield
width, and 152 GPU-driver compiles stopped there
(feature-nodisx-linux-gpu-drivers-built-by-pxx). Three things were wrong in
the constant folder (CEvalConst*):

1. __builtin_clz/ctz/popcount/ffs (with the l and ll forms) did not fold. They
   were read as an unknown `__` name: the folder marked the expression
   non-constant and read 0, so `63 - __builtin_clzll(8)` in an enum was
   silently 63. They now fold the way gcc folds them (CBitBuiltinKind).
2. CEvalConstTernary decided whether the else-arm was live from a flag the
   then-arm could set. A run-time value in the TAKEN arm made the untaken
   arm count. The condition's own flag is now captured before either arm.
3. A dead arm holding _Generic is skipped by its tokens (CEvalConstDeadArm).
   The folder has no _Generic, and an untaken arm's value is never needed.

Test row c_paintq26 covers the bitfield widths, an enum, an array dimension,
the run-time _Generic call, and the folded values, all against gcc.
