---
track: N
prio: 20
type: bug
---

# A lambda's object capture dangled once the enclosing call returned

Found 2026-10-20 in Vloot's hover rows, once the lambdas were compiled (see
bug-nilpy-a-lambda-capturing-a-str-cannot-call-a-def):
`clickable([row, title], ...)` binds `lambda e: paint(hover_bg)` and returns.
On <Enter>, `paint` walked `widgets` (a list) that had already been freed
(rc 139; `len(widgets)` read 1634887022).

**Cause:** the lambda lifter bound a class-typed capture with the plain
`pyboundfn_bind`, which takes no reference. A nested def taken as a value
already used the retaining `pyboundfn_bind_obj`
(PyNestedDefClosureValue).

**Fix:** the lifter binds tyClass captures through `pyboundfn_bind_obj`,
whose finaliser releases the reference with the closure.

Test: test_nilpy_lambda_capturing_a_str_calls_a_def (hover_rows) and
examples/tk/sidebar_cards_and_hover_rows.
