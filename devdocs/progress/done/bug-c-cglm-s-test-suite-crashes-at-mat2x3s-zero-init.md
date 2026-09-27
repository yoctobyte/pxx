---
track: C
prio: 50
type: bug
status: done
found: 2026-09-27
found-by: frankD
owner:
summary: "cglm's own test suite (the v425 restamp kit's drv/cglm_all.c) now passes 1109 tests (of 1132 TEST_ENTRY lines in test/tests.h) with no failure and then segfaults in `mat2x3s_zero_init`, the first test of the struct API: `mat2x3s m = GLMS_MAT2X3_ZERO_INIT; test_assert_mat2x3_eq_zero(m.raw);`, where mat2x3s is a UNION of `mat2x3 raw` (an array typedef), `vec3s col[2]` and an anonymous struct. Not yet reduced; the suspects are the union's array-typedef member initialised from a braced macro, and `.raw` decaying as a call argument. Before bug-c-an-array-of-pointers-to-arrays-has-no-pointee-shape-so-deref-loads-instead-of-decaying the suite (on the v441 pin) passed 88 and stopped at the assertion in glm_mat4_mulN."
---

# cglm's test suite crashes at `mat2x3s_zero_init`

Measured 2026-09-27 with the compiler that fixed
bug-c-an-array-of-pointers-to-arrays-has-no-pointee-shape-so-deref-loads-instead-of-decaying:

```
P=compiler/pascal26; L=library_candidates; K=/home/neo/pxx-website-patches/v425-restamp
$P -Ilib/crtl/include -Ilib/crtl/src -I$L/cglm/include -I$L/cglm/test/include \
   -I$L/cglm/test/src $K/drv/cglm_all.c /tmp/cglm && /tmp/cglm
```

rc=139 after `glmc_ivec4_abs`. The next entry in `test/tests.h` is
`mat2x3s_zero_init` (test/src/test_struct.c:10). Reduce it against gcc before
guessing the mechanism.

## 2026-09-27 (frankD): the same bug as the struct-field ticket, fixed there

`mat2x3s` is a union whose `raw` member is typed by the array typedef
`mat2x3`; the struct builder laid it out as one float, so `.raw` passed on as
a `mat2x3` read past it. Fixed with
bug-c-a-struct-field-that-points-at-an-array-typedef-has-no-pointee-dims.
cglm's whole suite now runs: 1131 ran, 1131 passed, 0 failed, rc=0.

## Log
- 2026-09-27 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
