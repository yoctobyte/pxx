# C GNU statement expressions ({ ... }) + __builtin_expect

- **Type:** feature (GCC extension, kernel-style code). Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing tests
- 00213: statement exprs in dead ternary arms containing labels — code
  suppression semantics. "expected C expression" line 15.
- 00214: `({ ... })` value-yielding blocks + `__builtin_expect(!!(x), 0)`
  (expect can be a pass-through builtin returning arg 1).

Needed for tcc/zlib-adjacent real-world code (corpus plan step 2/3).

## Gate
Drop 00213.c/00214.c from test/c-conformance/pxx.skip; runner green.
