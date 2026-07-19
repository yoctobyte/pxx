---
track: A
prio: 50
type: feature
---

# Shared-parser hook for NilPy str methods (filed for traceability)

Track N's [[feature-nilpy-str-methods]] needs one branch in the SHARED
`compiler/parser.inc`, which is Track A/P ground — filed per the
combined-track rule and self-resolved (the same session held A and N, with no
other agent on A).

## What was added

`parser.inc` gains exactly two things, both `PyExprMode`-gated so the Pascal
dialect is untouched:

- a forward declaration of `PyParseStrMethod` (mirroring the existing
  `PyParseListLiteral` forward — `pyparser.inc` is included after
  `parser.inc`, so this is how the shared parser reaches N's code);
- a branch in the postfix `.member` path that, when the base is string-typed
  and the next token is `(`, delegates to `PyParseStrMethod` and feeds the
  call's return type back into the suffix loop so chains keep parsing.

All method-set knowledge lives in `pyparser.inc` and `pylib.pas` (Track N /
Track B files). The shared parser only learns WHERE the form is legal, not
what it means — so growing the method set never touches A's ground again.

Gate: `test-nilpy` GREEN, `--tier quick` GREEN, self-host fixedpoint
byte-identical.
