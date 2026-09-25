---
prio: 45
track: C
summary: 'An ELEMENT that is a pointer to an array has no channel to record its pointee''s shape. The metadata that makes `float (*p)[4][4]` work (SymPtrElemArrLen/NDims/DimSpan) describes the SYMBOL''s own pointee, so it cannot describe an array of such pointers (`mat4 *ms[3]`) or a pointer to one (`mat4 **m`, which is what the parameter `mat4 *m[]` becomes). As a result `*ms[i]` LOADS from the matrix where C decays it to the matrix''s address, and `(*ms[i])[r][c]` strides by elements. Passing `*ms[i]` on as a `mat4` argument segfaults. This is the body of cglm''s glm_mat4_mulN, whose own call site `(mat4 *[]){&a,&b,&c}` parses since this ticket was filed. The spelled-out form `float (*sp[2])[4][4]` is refused outright ("expected C expression"). Measured 2026-09-25: both the compiler built at 2ae5962be3 and the one after the fix segfault on the named-array spelling, so it is not a regression.'
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
