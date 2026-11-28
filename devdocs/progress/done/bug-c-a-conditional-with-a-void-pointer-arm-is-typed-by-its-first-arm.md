---
title: "C: a ?: with a void * arm took its first arm's pointee; sizeof(*void_ptr) was 4"
status: done
owner: claude-dupwt
prio: 75
area: cfront
---

C11 6.5.15p6: when one arm of `?:` is a null pointer constant, the result
has the other arm's type. Otherwise a `void *` arm makes the result
`void *`. pxx always took the then-arm's pointee. Separately, `sizeof *p`
of a `void *p` was 4, where GNU C says 1 (pointer arithmetic on void * already
stepped by 1).

Together these broke Linux's __is_constexpr(x),
`sizeof(int) == sizeof(*(8 ? ((void *)((long)(x) * 0l)) : (int *)8))`, which
pxx answered 1 for every x. LinuxKPI and i915 use it to choose an arm of
__builtin_choose_expr, and min()/max() use it to choose between the
evaluate-once and the plain comparison, so a wrong answer can evaluate a side
effect twice. Found in the GPU-driver census
(feature-nodisx-linux-gpu-drivers-built-by-pxx).

Fix:
- CNodeIsNullPtrConst: an integer constant 0, optionally cast to `void *`
  (CBakeIntValue decides "constant").
- The AN_TERNARY arm of CNodePointeeTk follows 6.5.15p6.
- sizeof of a void deref answers 1, in both the general arm and the
  pointer-identifier arm.

Test row c_voidcond26, whose expected output is gcc's.
