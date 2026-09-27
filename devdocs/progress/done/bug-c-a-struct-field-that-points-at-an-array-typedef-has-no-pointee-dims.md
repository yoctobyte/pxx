---
track: C
prio: 60
type: bug
status: done
found: 2026-09-27
found-by: frankD
owner: frankD
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

## 2026-09-27 (frankD): fixed, and the root was wider than the pointer fields

The struct builder (ParseCStructInto) never read the member type's array-typedef
dims at all. So:
- a member TYPED by an array typedef (`mat4 m;`, `arr3 a;`, `vec4 rows[2];`)
  was laid out as ONE element: `struct { int k; mat4 m; vec4 v; }` 12 bytes,
  gcc 84; `struct U { arr3 a; int after; }` 8, gcc 16, and `u.a[1] = 2`
  overwrote `after`. Silent memory corruption, v441 and v443 alike;
- a member POINTING at one (`mat4 *p;`, `mat4 *m[3];`) had no pointee dims
  (only a flat length, and the plain-declarator arm set even that to 0);
- cglm's `union mat2x3s { mat2x3 raw; ... }` crashed on `chk(a.raw)`, the
  first test of cglm's struct API. That ticket
  (bug-c-cglm-s-test-suite-crashes-at-mat2x3s-zero-init) is this bug.

Fix:
- the member's typedef dims are captured when its type is parsed and folded
  after the bracket dims when the declarator has no stars; with one star they
  become the pointee's shape, in the new UFldPtrElemNDims / UFldPtrElemDimSpan
  (separate from UFldArrDimSpan, so an ARRAY of such pointers keeps both);
- the anonymous-member flattening now copies dims and pointee shape (it
  dropped a multi-dim member's dims to 0);
- the spelled-out `float (*fp)[4][4];` member records its rows too;
- ONE READER: `CPtrToArrShape` (ir.inc) answers "what does this pointer-to-array
  value point at" for the symbol spellings and for `s.p`, `ps->p`, `s.m[i]`,
  filling CPA*. CDerefDecayStride, the subscript flatten, the `(*x)[i]` unwrap
  and IRPointerStride all read it; the token-based sizeof walk fills the same
  shape through CPtrShapeFromSym / CPtrShapeFromField.

Not covered: an array typedef of STRUCTS (`typedef P PA[2]`), which the
typedef table does not model at all; filed as
bug-c-an-array-typedef-of-structs-is-not-modelled (va_list has that shape).
A depth-2 pointer member (`mat4 **pp;`) has no base-pointee carrier and is
not stamped; not measured against gcc.

Evidence (x86-64, gcc 15):
- test/c_struct_member_of_array_typedef.c, 61 rows diffed against gcc, wired
  into test-core; the first block writes each member and reads its
  NEIGHBOURS. The v443 pin segfaults with 47 of 61 rows wrong;
- test/c_array_of_pointers_to_array_typedefs.c still 68/68 = gcc;
- cglm's suite (v425 kit drv/cglm_all.c): 1131 tests ran, 1131 passed,
  0 failed, rc=0 (was 1109 passes and a segfault at mat2x3s_zero_init).

## Log
- 2026-09-27 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
