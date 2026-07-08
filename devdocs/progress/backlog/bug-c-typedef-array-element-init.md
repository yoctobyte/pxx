---
prio: 45
---

# C: initializing a typedef-array (or array-of-typedef-array) local reads wrong / errors

- **Type:** bug (cparser typedef-array decl + init). Track C.
- **Found:** 2026-07-08 while landing bug-c-local-nested-aggregate-init
  (the recursive local walker fixed nested struct / anon-union / struct+subarray
  locals; this typedef-array case is separate).

## Cases (v4 = float[4] typedef)
```c
typedef float v4[4];
v4 r = {1,2,3,4};          /* compiles, but r reads wrong (returns garbage) */
v4 rows[2] = {{1,2,3,4},{5,6,7,8}};   /* error: expected C expression */
```
`v4 r[2];` with no initializer WORKS (indexing is fine), so the array-of-
typedef-array LAYOUT is right; only the brace INITIALIZER path mishandles a
typedef whose expansion is itself an array. The element's hidden inner
dimension (the typedef's [4]) is not threaded into the init walker's dim
metadata, so the nested braces don't map to element sub-arrays.

## Direction
When a declarator's element type is a typedef that expands to a fixed array,
fold the typedef's dimension(s) into the symbol's SymArrNDims/SymArrDimSpan
(so `v4 rows[2]` becomes a 2-dim [2][4] array), then the existing local
recursive walker (CInitLocalAggregate, isArr) covers the init. The bare `v4 r`
single case similarly needs the typedef dim recorded on r.

## Blocks
cglm (glm_frustum_corners' `vec4 csCoords[8] = {{...},...}` — vec4 = float[4]).

## Gate
Both cases read correct; cglm probe advances past this; c-conformance +
corpus green; self-host byte-identical.
