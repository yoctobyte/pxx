---
prio: 55  # auto
---

# C switch: non-compound body + case labels inside nested statements (Duff's device)

- **Type:** bug (cparser statement lowering). Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing tests
- 00051: `switch(x) case 0: ;` — switch body is any STATEMENT, not necessarily a
  `{...}` block. Error "Expected: {, but got: case". Also case labels inside a
  nested plain block within the switch braces.
- 00143: Duff's device — `case` labels inside a `do {...} while` nested in the
  switch. Compiles but exit 1 (wrong copy) → dispatch doesn't jump into the loop.

## Root cause
Switch lowered as structured case-list instead of C semantics: `case`/`default`
are LABELS on arbitrarily nested statements inside the switch body; dispatch is
a computed goto to the matching label.

## Gate
Drop 00051.c/00143.c from test/c-conformance/pxx.skip; runner green.
