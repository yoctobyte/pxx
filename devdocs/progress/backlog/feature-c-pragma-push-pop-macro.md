# C preprocessor: #pragma push_macro / pop_macro

- **Type:** feature (cpreproc). Track C. Small.
- **Found:** 2026-07-06 c-testsuite run.

## Failing test
- 00206: `#pragma push_macro("abort")` / `pop_macro` save/restore macro
  definitions (stack per name). We ignore the pragma → last #define sticks
  (prints 333/333 instead of 222/111 after pops). Also: a user macro NAMED
  `pop_macro`/`push_macro` must not confuse the pragma.

## Gate
Drop 00206.c from test/c-conformance/pxx.skip; runner green.
