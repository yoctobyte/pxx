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
