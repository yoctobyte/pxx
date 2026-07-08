---
prio: 55
---

# C: calling through an INLINE fn-pointer parameter — "call to undeclared function"

- **Type:** bug (cparser param declarators). Track C.
- **Found:** 2026-07-08 game-library ladder, stb_sprintf.h first probe
  (feature-game-library-candidate-suite); long-known in principle — the crtl
  qsort comment (lib/crtl/src/stdlib.c) already works around it with a typedef.

## Repro
```c
int apply(int (*cb)(int), int x) { return cb(x); }
/* pascal26: error: call to undeclared function: cb */
```
Typedef'd form works (`typedef int (*fn)(int); int apply(fn cb, int x)`), so
the inline `T (*name)(params)` PARAM declarator never records its call
signature (SymProcSig) the way the typedef path does.

## Blocks
- stb_sprintf.h (stbsp__vsprintfcb's `callback` param, line ~418) — the whole
  stb single-header family leans on this idiom.
- Any qsort-style API written without a typedef.

## Gate
stb probe `test/gamelib/stb_sprintf_probe.c` compiles+passes; the crtl qsort
typedef workaround can be dropped; regression bXXX; c-conformance + corpus
green + self-host.

## Log
- 2026-07-08 — resolved, commit 0c2a3329.
