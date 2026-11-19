---
slug: bug-c-aligned-alignof-long-double-on-i386
track: C
prio: 50
type: bug
status: done
owner: rd
created: 2026-11-19
found-by: rd, classifying c_incomplete_type_member_refused in the 2026-11-19 test-core sweep
tags: [cfront, attributes, abi, i386]
blocked-by: []
summary: "`struct s { int a, b; } __attribute__((aligned(__alignof__(long double))))` is 16/16 (size/align) on i386 under pxx, 8/4 under gcc -m32. CAttrAlignExprAt (clexer.inc) answers 0 for `long double` (\"unknown here\"), and since b3c5f711ea a 0 takes the target's biggest alignment (16) with a warning instead of making the struct opaque. Right on x86-64 and aarch64 (gcc: 16), wrong on i386 (gcc: 4). Underneath: pxx's long double is double (8/8) on every target, so the fix must decide what __alignof__(long double) answers inside an attribute versus in an expression."
---

# aligned(__alignof__(long double)) on i386

Measured 2026-11-19 on b2cd388a0c:

| target  | pxx size/align | gcc size/align |
|---------|----------------|----------------|
| x86-64  | 16 / 16        | 16 / 16        |
| aarch64 | 16 / 16        | 16 / 16 (AAPCS64 long double; not run) |
| i386    | 16 / 16        | 8 / 4 (-m32)   |

`_Alignof(long double)` in an expression says 8 on every pxx target
(long double is double), so the attribute path and the expression path
already disagree, and both disagree with gcc's ABI on x86-64 (16) and i386 (4).

The smallest fix is a per-target table for `long double` in
CAttrAlignExprAt (x86-64/aarch64/riscv32 16, i386 4, arm32/xtensa 8). It
would also be right to make CAttrAlignExprAt tell sizeof from alignof: today
both return the size, so `__alignof__(long long)` on i386 answers 8 where
gcc says 4.

## Fixed (2026-11-19, rd)

CAttrAlignExprAt answers long double per target, as gcc lays it out:
sizeof/alignof x86-64, aarch64, riscv32 16/16; i386 12/4; arm32, xtensa
8/8. `__alignof__` and `sizeof` are told apart for it (only long double
differs; double and long long are 8 under gcc -m32 `__alignof__` too).
test/c_aligned_alignof_long_double.c: x86-64 "16 16 7 9 8 8", i386
"8 4 7 9 8 8", both gcc's. c_incomplete_type_member_refused no longer
warns at all. aarch64 checked against the AAPCS64 value (no cross gcc).
