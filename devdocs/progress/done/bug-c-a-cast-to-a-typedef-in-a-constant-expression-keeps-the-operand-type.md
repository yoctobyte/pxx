---
slug: bug-c-a-cast-to-a-typedef-in-a-constant-expression-keeps-the-operand-type
track: C
prio: 60
type: bug
status: done
owner: pxx2
created: 2026-11-25
closed: 2026-11-25
found-by: pxx2 (libdrm for Path B Xorg)
tags: [cfront, constexpr, typedef]
summary: "`(off_t)1 << 31` in a constant expression folded as an int shift (to INT_MIN), so libdrm's large-file assertion `LARGE_OFF_T % 2147483629 == 721` failed with a negative array size. CConstCast recognised the builtin type words but treated any other identifier as an unknown type and left the operand's width. New CConstCastTypedef resolves a typedef name to its width and signedness (pointer and array typedefs as pointers). Test c_xgaps26."
---

# Cast to a typedef in a constant expression keeps the operand type

libdrm's configure-time check, also inside its sources:

```c
#define LARGE_OFF_T ((((off_t) 1 << 31) << 31) - 1 + (((off_t) 1 << 31) << 31))
int off_t_is_large[(LARGE_OFF_T % 2147483629 == 721 && LARGE_OFF_T % 2147483647 == 1) ? 1 : -1];
```

The constant folder now widens `(off_t)1` to 64 bits, as gcc does. Enum
values with `(L)1 << 40` and `(U16)70000` are checked too.
