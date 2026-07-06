---
prio: 45  # auto
---

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

## Update 2026-07-07
The const-fold half advanced: the constant-expression evaluator now handles
?: || && and comparisons (commit 41dac3b8), so `int a[1 && 1]` and `int b[1 || 1]`
array bounds fold correctly. Remaining for 00207:
- `int c[1 ? 3 : 9]` — a ternary directly in an ARRAY BOUND still fails to parse
  (scalar/enum/global ternary works; the array-dim path stops mid-ternary — a
  separate small edge, likely the dim reader in ParseCDeclType vs
  ParseCLocalDeclAST double-reading or a token-position issue).
- VLA `char test[argc]` (runtime-sized array) — the big part.
- label as the sole statement of a braceless `if`.

## Trace 2026-07-07 — array-bound ternary else-branch bug pinned
Instrumented CEvalConstTernary on `int a[2?3:4]`: cond done (CurTok=tkQuestion),
then-branch = 3 (correct, CurTok=tkColon), after consuming ':' CurTok = the `4`
integer token — but the ELSE-branch `e := CEvalConstTernary` returns 2, not 4,
and leaves CurTok on that integer (so the array loop's Expect(']') fails).
So the else-branch reads the WRONG value / mis-tracks token position, but ONLY
in the array-dim eval context (scalar/enum/global const ternary is correct).
Subtle mutual-recursion / token-position bug in the const evaluator's array-dim
call path — needs focused debugging (compare TokPos handling of the array-dim
CEvalConstExpr call site vs the scalar-init one).
