---
slug: bug-c-if-right-shift-of-a-negative-value-is-logical
track: C
prio: 70
type: bug
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (Panorama all-pxx program: libxkbcommon 1.13.1 through compdb.py replay)
tags: [cpreproc, if-expr]
summary: "`#if (-8 >> 1) != -4` was TRUE: the #if evaluator shifted a negative Int64 with Pascal's logical `shr`. gcc defines a signed `>>` as arithmetic, and pxx's own codegen does the same. libxkbcommon's state.c guards a bit-field with `(-XKB_MAX_GROUPS) < (INT32_MIN >> 2)` and hit its own #error. A negative left operand now shifts as `not ((not v) shr n)`; unsigned is unchanged. Test: c_xkbpp26."
---

# C if right shift of a negative value is logical

Measured against gcc on `(INT32_MIN >> 2)`, `-8 >> 1`, `-1 >> 63`, `-8 >> 0`, an unsigned
`0xFFFFFFFFFFFFFFF8 >> 1` and `-8 >> 1u`. All six agree after the fix (CPExprShift in cpreproc.inc).
