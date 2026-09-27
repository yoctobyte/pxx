---
track: C
prio: 35
type: bug
status: open
found: 2026-09-25
found-by: frankD
owner:
summary: "The spelled-out declarator for an array of pointers to arrays, `float (*q[2])[4] = {&a, &b};` and `float (*m[2])[4][4]`, is refused with \"expected C expression\". The typedef spelling (`vec4 *q[2]`, `mat4 *m[2]`) is the same type and works since bug-c-an-array-of-pointers-to-arrays-has-no-pointee-shape-so-deref-loads-instead-of-decaying; this is the declarator parse only. Loud, not wrong. Same on the v441 pin."
---

# The spelled-out array-of-pointers-to-arrays declarator is refused

```c
float a[4] = {1,2,3,4}, b[4] = {5,6,7,8};
float (*q[2])[4] = {&a, &b};     /* pxx: error: expected C expression */
printf("%d %d %d\n", (int)sizeof q, (int)sizeof q[0], (int)sizeof *q[0]);  /* gcc 16 8 16 */
```

The `( * ident ) [` detector in ParseCDeclType takes `(*name)[N]` and the
fn-pointer arm takes `(*name[N])(...)`; `(*name[N])[M]` matches neither. When
it is parsed, stamp the pointee exactly as the typedef spelling does (the
array-arm block after SetSymPointerType in the local path, and its global
twin), so the two spellings share one carrier and one reader
(CPtrToArrShapeSym).
