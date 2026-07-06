---
prio: 28  # auto
---

# C11 _Generic selection

- **Type:** feature (cparser). Track C. Low priority (C11, rare in target corpus).
- **Found:** 2026-07-06 c-testsuite run.

## Failing test
- 00219: `#define gen_sw(a) _Generic(a, const char *: 1, default: 8, int: 123)`
  plus assorted controlling-expression type checks. "expected C expression".
  Compile-time type dispatch: pick assoc whose type matches the controlling
  expr (after lvalue conversion), else default.

## Gate
Drop 00219.c from test/c-conformance/pxx.skip; runner green.

## Triage note 2026-07-07
Not bounded: 00219 distinguishes types with full C precision — `const char *` vs `int`, `int *` vs `int * const` (const-qualified pointer), `struct a` vs `struct b`, `int[4]`, `int **`, `long` vs `long long` vs `int`, function-pointer types, signed/const int variants. pxx does not track const-qualification, pointer-const, or full integer-width distinctions in its type model, so real _Generic dispatch needs a much richer C type representation + a type-compatibility matcher. Large feature, not a parser-only add.
