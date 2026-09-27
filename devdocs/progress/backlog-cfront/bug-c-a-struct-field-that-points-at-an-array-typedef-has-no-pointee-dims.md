---
track: C
prio: 60
type: bug
status: open
found: 2026-09-27
found-by: frankD
owner:
summary: "A struct FIELD whose type is a pointer to an array typedef is silently wrong, in both the scalar spelling (`mat4 *p;`) and the array-of-pointers one (`mat4 *m[3];`). Field pointee metadata is one flat length (UFldPtrElemArrLen) with no dims, so `sizeof *s.p` is 4 (gcc 64), `(*s.p)[2][2]` reads 0 (gcc 3), `sizeof *s.v` for `vec4 *v` is 4 (gcc 16), and `(*s.m[0])[1][1]` segfaults. Same answers on the v441 pin and after the fix for variables (bug-c-an-array-of-pointers-to-arrays-has-no-pointee-shape-so-deref-loads-instead-of-decaying), which gave SYMBOLS the carrier and the one reader CPtrToArrShapeSym; fields need the twin of both. Found by varying that fix's shape."
---

# A struct field that points at an array typedef has no pointee dims

Measured 2026-09-27 with the v441 pin (sha256 `4ebfa2d047a2`) and with the
compiler that fixed the variable spellings, against gcc 15. Both pxx columns
are identical:

```c
typedef float vec4[4]; typedef vec4 mat4[4];
struct S { int k; mat4 *p; vec4 *v; mat4 *m[3]; vec4 *vm[2]; };
mat4 a = {{1},{0,2},{0,0,3}}; vec4 w = {1,2,3,4};
struct S s; s.p = &a; s.v = &w; s.m[0] = &a; s.vm[1] = &w;
```

| expression | gcc | pxx |
| --- | --- | --- |
| `sizeof s` | 64 | 64 |
| `sizeof *s.p` | 64 | 4 |
| `(*s.p)[2][2]` | 3 | 0 |
| `s.p[0][1][1]` | 2 | 0 |
| `sizeof *s.v` | 16 | 4 |
| `(*ps->p)[1][1]` | 2 | 0 |
| `sizeof s.m`, `sizeof s.m[0]` | 24, 8 | 24, 8 |
| `sizeof *s.m[0]` | 64 | 8 |
| `(*s.m[0])[1][1]` | 2 | segfault |

Fix shape: a field twin of the symbol carrier (pointee NDims and spans per
field, stamped by the struct builder where it already stamps
UFldPtrElemArrLen), and teach `CPtrToArrShapeSym`'s consumers
(CDerefDecayStride, the pointer-to-array subscript arm, IRPointerStride, the
sizeof descriptor walk) to take a field. Probe kit: the variable test
`test/c_array_of_pointers_to_array_typedefs.c` is the model.
