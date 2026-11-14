---
track: C
prio: 30
type: bug
status: done
found: 2026-09-27
found-by: frankD
owner:
summary: "`sizeof (*p)[1]` is refused with \"expected ')'\" where gcc answers the row size (16 for `mat4 *p`). The unparenthesised-operand sizeof reads `(*p)` as a parenthesised TYPE-or-expression and does not continue into the postfix `[1]`. Loud, not wrong. Same on the v441 pin. Seen for `mat4 *p` and for `mat4 *m[]` (`sizeof (*m[0])[1]`)."
---

# `sizeof (*p)[1]` is refused

```c
typedef float vec4[4]; typedef vec4 mat4[4];
mat4 a; mat4 *p = &a;
printf("%d\n", (int)sizeof (*p)[1]);   /* gcc 16; pxx: error: expected ')' */
```

Measured 2026-09-27 on the v441 pin and after
bug-c-an-array-of-pointers-to-arrays-has-no-pointee-shape-so-deref-loads-instead-of-decaying;
both refuse. `sizeof((*p)[1])` with outer parentheses has not been measured
separately.

## Resolved 2026-11-14

Fixed together with the call form: CSizeofOperandHasTrailingPostfix sees an
unparenthesised operand whose group, `(...)` or a call `f(...)`, is followed by
`[` (or by `.`/`->` after a call), and that operand is parsed whole by
ParseCUnary and sized by CSizeofNodeBytes (the parenthesised general arm's
rules). `sizeof (v)[i]` of a plain variable keeps the descriptor walk.

Test: test/c_declarator_and_sizeof_shapes.c, `sizeof (*p)[1]` and
`sizeof (*mm[0])[1]` = 16 as gcc.
