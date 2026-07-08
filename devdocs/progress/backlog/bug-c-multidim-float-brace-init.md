---
prio: 35
---

# C: a 2-D (multi-dim) brace initializer of a FLOAT element array zero-fills

- **Type:** bug (cparser array init). Track C.
- **Found:** 2026-07-08 while landing array typedefs
  ([[bug-c-typedef-array-element-init]]).

## Symptom
```c
float m[2][4] = {{1,2,3,4},{5,6,7,8}};   /* all elements read 0.0 */
typedef float vec4[4];
vec4 rows[2] = {{1,2,3,4},{5,6,7,8}};    /* same — folds to [2][4], zero-filled */
```
1-D float brace init works (`float v[4] = {1,2,3,4}`); multi-dim element access
and element-wise assignment work; only the multi-dim BRACE INITIALIZER of a
float element array drops the data.

## Root cause
`ParseCLocalDeclAST`'s `dimCount >= 2` brace-init path (cparser.inc ~2775) is
gated `TypeIsOrdinal(declTk)` — floats (tySingle/tyDouble) are excluded, so the
nested-brace element parse never runs and the array stays zero. The 1-D float
path (`dimCount <= 1`) has no such gate. The global path likely mirrors this.

## Fix direction
Extend the `dimCount >= 2` brace-init element parse to accept float element
types (the per-element `ParseCExpr` + flattened index stores already handle
floats — it is only the `TypeIsOrdinal` guard blocking entry). Mirror in the
global decl path if it has the same gate.

## Gate
`float m[2][4] = {{...},{...}}` and the `vec4 rows[2]` typedef form read back
correct values; a focused repro; c-conformance + corpus green.
