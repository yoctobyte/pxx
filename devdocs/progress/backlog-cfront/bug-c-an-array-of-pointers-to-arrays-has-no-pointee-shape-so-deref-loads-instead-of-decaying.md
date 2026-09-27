---
prio: 70
track: C
summary: 'An ELEMENT that is a pointer to an array has no channel to record its pointee''s shape. The metadata that makes `float (*p)[4][4]` work (SymPtrElemArrLen/NDims/DimSpan) describes the SYMBOL''s own pointee, so it cannot describe an array of such pointers (`mat4 *ms[3]`) or a pointer to one (`mat4 **m`, which is what the parameter `mat4 *m[]` becomes). As a result `*ms[i]` LOADS from the matrix where C decays it to the matrix''s address, and `(*ms[i])[r][c]` strides by elements. Passing `*ms[i]` on as a `mat4` argument segfaults. `sizeof` of such an array is SILENTLY wrong as well when the element is a typedef of an array typedef (a count computed as `sizeof a / sizeof a[0]` comes out 1), which is the first thing cglm's own test suite hits once it builds. This is the body of cglm''s glm_mat4_mulN, whose own call site `(mat4 *[]){&a,&b,&c}` parses since this ticket was filed. The spelled-out form `float (*sp[2])[4][4]` is refused outright ("expected C expression"). Measured 2026-09-25: both the compiler built at 2ae5962be3 and the one after the fix segfault on the named-array spelling, so it is not a regression.'
---

# An array of pointers to arrays has no pointee shape

Repro (gcc prints `16 6 6`, pxx segfaults):

```c
typedef float vec4[4]; typedef vec4 mat4[4];
static float mulN(mat4 *m[], int n) { float s = 0; int i;
  for (i = 0; i < n; i++) s += (*m[i])[i][i]; return s; }
int main(void) { mat4 a = {{1},{0,2}}, b = {{5},{0,6},{0,0,7}}, c = {{9},{0,9},{0,0,9},{0,0,0,9}};
  mat4 *arr[3] = {&a, &b, &c};
  printf("%g %g\n", mulN(arr, 3), (*arr[1])[1][1]); }
```

cglm's own shape is `mul(*matrices[0], *matrices[1], dest)`, which needs only
the decay.

Scope: this is a second level of pointee description. A symbol whose ELEMENT
(for an array) or whose pointee's pointee (for a depth-2 pointer) is an array
of known dims. The consumers are:
- CDerefDecayStride (the `*x[i]` decay);
- IRPointerStride and the multi-subscript flatten (`(*x[i])[r][c]`);
- sizeof;
- the declarator parse of `T (*name[N])[A][B]`.

Stamped today, all at depth 1:
- `mat4 *q` locals and params;
- `(mat4 *)e` casts;
- the array-of-pointer compound literal temp, which carries only the element
  record.

## 2026-09-27 (frankD): the sizeof consumer gives a SILENT wrong count, and that is cglm's first failure

Measured with the v441 pinned binary (sha256 `4ebfa2d047a2`, commit `5c1696ca79`),
tree `ab1960b987`, against gcc 15 on the same host:

```c
typedef float vec4[4]; typedef vec4 mat4[4];
mat4 a, b, c; mat4 *m[] = { &a, &b, &c }; mat4 *p = &a;
printf("%d %d %d %d\n", (int)sizeof(m), (int)sizeof(m[0]), (int)sizeof(p), (int)(sizeof(m)/sizeof(m[0])));
```

gcc `24 8 8 3`, pxx `128 128 8 1`. With `vec4 *m[]` (one level of array typedef)
pxx agrees with gcc (`16 8 16 16` for `m`, `m[0]`, `vec4 *n[2]`, `float (*q[2])[4]`).
cglm's own test suite (the v425 restamp kit's `drv/cglm_all.c`) now BUILDS on v441,
where v425 refused it, and runs until `mat4_mulN`, which passes
`sizeof(matrices) / sizeof(matrices[0])` = 1 and trips cglm's `len > 1` assertion
(rc=134). So the observable reached first is a wrong count with no diagnostic, not
the segfault in the repro above.

Re-ranked 45 -> 70 on 2026-09-27 (frankuser, coordinator): a silent wrong value on real code (cglm) ranks above a refusal. docs/reference/known-issues.md carries a "Silently wrong" row for it until the fix lands; remove that row in the fixing commit. Note the size is not a simple multiple: `sizeof m` is 128 for three elements (neither 3x8 nor 3x64), so do not assume "pointee size per element" without printing it.
