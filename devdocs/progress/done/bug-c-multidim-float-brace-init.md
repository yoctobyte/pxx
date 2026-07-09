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

## LOCAL case fixed 2026-07-08 (a-agent) — GLOBAL remains
The block-scope path is fixed: the `dimCount >= 2` brace gate in
`ParseCLocalDeclAST` now accepts `TypeIsFloat(declTk)` too, so
`float m[2][4] = {{..},{..}}` and `vec4 rows[2] = {{..},{..}}` read back correct
locally (guard: test/carray_typedef_element_init.c). Committed with the
array-typedef feature.

STILL OPEN — **file-scope (global)** 2-D float brace init:
```c
float gm[2][4] = {{1,2,3,4},{5,6,7,8}};   /* reads 0 0 0 */
```
The global init in `ParseCGlobalVarDecl` emits to the data section via a
different value-collection path (arrOffs/arrKind, ~cparser.inc:4514+) that does
not cover a multi-dim FLOAT brace group. Fix there mirrors the local relax but
must emit float bit patterns into the global data blob.

## Gate
`float gm[2][4] = {{...},{...}}` at file scope reads back correct; a focused
repro; c-conformance + corpus green.

## GLOBAL case fixed 2026-07-09 (cfront-agent) — ticket closed
The file-scope path now works. `ParseCGlobalVarDecl`'s multidim brace-init route
(cparser.inc ~4876) was gated `TypeIsOrdinal(baseTk)`, excluding tySingle/tyDouble;
the flat-FLOAT path (~4929) is 1-D only — so `float gm[2][4]={{..},{..}}` fell
through to the skip path and read 0.0. Relaxed the gate to
`(TypeIsOrdinal(baseTk) or TypeIsFloat(baseTk))` so multidim float globals route
through the recursive brace-elision walker (CEmitDeferredCAggInits →
CInitWalkArray), whose leaf store already handles floats (same path the LOCAL fix
used). Flat float (dimCount 1) still hits the 1-D float path — no regression.
Repro test/cmultidim_float_global_b205.c (exit 42; float+double+typedef-vec4+
elided+partial). c-conformance 213/0/7, self-host byte-identical, quick green.
