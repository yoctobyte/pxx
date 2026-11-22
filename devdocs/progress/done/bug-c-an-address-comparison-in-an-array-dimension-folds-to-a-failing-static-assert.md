---
slug: bug-c-an-address-comparison-in-an-array-dimension-folds-to-a-failing-static-assert
track: C
prio: 40
type: bug
status: done
created: 2026-11-22
found-by: claude-pxx (building micropython v1.24.1's unix port with pxx)
tags: [cfront, constexpr]
blocked-by: []
summary: "DONE 2026-11-22: `&object` in a constant expression folded to 0, so `sizeof(char[1 - 2 * !(&a != &b)])` -- micropython's MP_STATIC_ASSERT_NONCONSTEXPR inside mp_obj_is_type -- read `0 != 0` and was refused as a negative dimension in 24 files. The address of an object or function now marks the expression non-constant, so the array is a run-time VLA as in gcc; offsetof-style `&((T*)0)->f` still folds. Test c_addrdim26."
---

# An address comparison in an array dimension folds to a failing static assert

micropython's py/obj.h:

```c
#define MP_STATIC_ASSERT_NONCONSTEXPR(cond) ((void)sizeof(char[1 - 2 * !(cond)]))
#define mp_obj_is_type(o, t) (MP_STATIC_ASSERT_NONCONSTEXPR((t) != &mp_type_int), ...)
```

`&mp_type_int` is an address constant, not an integer constant expression. gcc
makes the array a VLA and evaluates `1 - 2 * !(1)` = 1 at run time. In
CEvalConstPrimary, pxx's tkAmp arm went to CEvalConstOffsetofAddress, which
gives 0 for a named object. So the comparison became `0 != 0`, the dimension
became -1, and 24 files failed to compile.

Fix: when `&` is followed by an identifier naming a variable or a function,
CConstExprSawNonConst is set (and the value is 1, never 0, so `&x && 1` and
`!&x` keep their truth value). The dimension path already turns
SawNonConst into a run-time VLA. Test: test/c_address_compare_in_dimension.c
(row c_addrdim26), which matches gcc.
