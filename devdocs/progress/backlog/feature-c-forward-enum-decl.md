# C forward enum declaration `enum efoo;` (GCC extension, common in the wild)

- **Type:** feature (cparser). Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing test
- 00170: `enum efoo;` before definition, used in prototypes/struct fnptr members
  before the `enum efoo { ... }` definition — "unresolved forward: deref_uintptr".
  Not ISO C but GCC accepts (pedantic warning only); test comment says it happens
  in real code. (The odd "deref_uintptr" unresolved suggests the enum parse
  failure derails later function registration too.)

## Gate
Drop 00170.c from test/c-conformance/pxx.skip; runner green.
