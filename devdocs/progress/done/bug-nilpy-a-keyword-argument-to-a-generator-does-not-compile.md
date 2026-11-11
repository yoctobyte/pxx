---
track: N
prio: 55
type: bug
status: done
---

# A keyword argument to a generator does not compile

Found 2026-10-19. With `def g(n, xs=None, d=acc): yield ...`, the call
`list(g(1, xs=7))` fails at compile time with `undefined variable (xs)`.
Positional `g(1, 7)` works, and so does a keyword argument to an ordinary def.
Pre-existing (12ddb7d995).

## Log
- 2026-11-11 — fixed. Value position (`list(g(1, xs=7))`) already worked
  since PyBuildGeneratorValueAt learned to bind keywords by name (nested
  generators work, cb5059e38e). The remaining failure was `for v in g(3,
  xs=4):`: the for-in desugar seeds the instance's argument slots in order and
  parsed `xs` as an expression. A call with a keyword argument
  (new PyCallHasKwArgAt) now skips that desugar and takes the value route.
  Test `test_nilpy_a_keyword_argument_to_a_generator.py` (row genkw26):
  keyword for a defaulted, a mutable-default and a positional parameter, a
  keyword-only parameter, and the for-loop form.
