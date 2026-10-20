---
track: N
prio: 20
type: bug
---

# A nested def's own `for` variable was taken as a capture

Found 2026-10-20 in Vloot: `def paint(colour): for w in widgets: ...`
nested in a function that also has a `w` was given the capture list
`w widgets`. A lambda that forwarded paint's captures had been built from the
earlier list (`widgets`), so its call came one argument short.

**Cause:** in Python `for` lexes as a plain tkIdent (PyParseFor asks
PyIsIdent('for')), but PyBodyBindsLocal and PyInUnpackTarget scan the
UNPARSED body for `tkFor`. The `for nm in` binding (and `for a, b in`) was
never seen, so the name was treated as a capture whenever the enclosing scope
had one.

**Fix:** PyTokIsFor accepts either form; both scans use it.

Test: test_nilpy_lambda_capturing_a_str_calls_a_def (hover_rows,
pairs_total).
