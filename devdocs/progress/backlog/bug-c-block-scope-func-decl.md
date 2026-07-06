---
prio: 55  # auto
---

# C block-scope function declaration `int f(char *);` inside a body fails

- **Type:** bug (cparser). Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing test
- 00078: prototype `int f1(char *);` declared INSIDE main (after other locals) —
  "pascal26:12: error: expected C expression". Local declaration path doesn't
  recognize function declarators; should register/refresh the prototype and emit
  no code. (Related: mid-block `extern` was rejected before too — v176 note.)

## Gate
Drop 00078.c from test/c-conformance/pxx.skip; runner green.
