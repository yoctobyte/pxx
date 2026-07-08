---
prio: 55
---

# C: LOCAL nested aggregate initializers fail ("expected C expression") — extend the elision walker to locals

- **Type:** bug (cparser local init lowering). Track C.
- **Found:** 2026-07-08 game-library ladder, cglm first probe
  (feature-game-library-candidate-suite).

## Repro (cglm glm_frustum_corners, typedef float vec4[4])
```c
vec4 csCoords[8] = { {-1.0f,-1.0f,-1.0f,1.0f}, ... };  /* local scope */
/* pascal26: error: expected C expression */
```
Array-of-array locals (typedef'd element arrays) with nested braces; float
literals. The GLOBAL side gained the recursive brace-elision walker
(bug-c-init-brace-elision-nested, e0f9f5e4) but locals still run the old
one-level loops in the local decl path (cparser.inc ~2680-3030), which choke
on element type = array.

## Fix sketch
Reuse `CInitWalkArray`/`CInitWalkRecord` (emit mode) at the local decl site —
they already build target AST chains and emit assignments via CompileAST; a
local just emits inline instead of deferring to main. Zero-fill first
(CMakeZeroLocal) since locals aren't BSS-zeroed. Needs the local's dim
metadata (dimSpan/SymArrNDims are already collected there).

## Blocks
cglm (header-only math — the whole probe battery), and any C code with
`T rows[N][M] = {{...}}` locals.

## Gate
test/gamelib/cglm_probe.c compiles+passes (42); c-conformance + corpus green;
self-host byte-identical.
