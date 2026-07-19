---
track: A
prio: 55
type: feature
---

# Shared parser: extend PyExprMode suppression to tkShl/tkXor

Filed under Track A (shared parser.inc) by the N-lane agent, self-resolved
per the combined-track rule (sole A holder confirmed this session).

ParseTerm consumed tkShl and ParseSimpleExpr consumed tkXor at Pascal
precedence even in PyExprMode, so NilPy's `1 << 2 + 3` parsed as
`(1 shl 2) + 3` = 7 instead of Python's `1 << (2+3)` = 32, and `^` never
reached the NilPy bitwise chain. Same mechanism as the existing
and/or suppression: gate both on `not PyExprMode`. Pascal paths unchanged
(PyExprMode is only set while parsing .npy expressions).

Resolved with [[feature-nilpy-operators]].
