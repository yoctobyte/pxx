# C VLA `char test[argc]` + label as sole statement of braceless if

- **Type:** feature (VLA) + parse bug. Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing test
- 00207: three regression fns from tcc history: (1) VLA `char test[argc]` with a
  label inside `if(0) label: printf(...)`; (2) goto into a block with arrays sized
  by CONSTANT logical/ternary exprs (`int a[1 && 1]` — not VLAs, must fold);
  (3) more label/goto shapes. Error "Expected: ], ... near: a >>>" at the
  `int a[1 && 1]` — const-expr folding of `&&`/`||`/`?:` in array bounds missing.

Split hint: const-expr array bounds (easy, real-world) vs VLA (big). Consider
fixing the const-fold part first; VLA may stay a documented skip.

## Gate
Drop 00207.c from test/c-conformance/pxx.skip; runner green (or re-tag skip as VLA-only).
