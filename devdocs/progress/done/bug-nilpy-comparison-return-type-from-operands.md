---
track: N
prio: 70
type: bug
---

# An unannotated def returning a COMPARISON typed its result from the operands

`PyInferDefRetType` reads the first `return <expr>` and asks
`PyInferExprType` for its type, and that scanner had no case for a comparison or
a membership test — it typed the expression by the OPERANDS it recognised:

```python
def is_bool_setting(section, key, value):
    return (section, key) in BOOLEAN_SETTINGS or value in {"0", "1"}   # -> TPyList
def bigger(a, b):
    return a > b                                                       # -> str
```

So the def's REGISTERED result type disagreed with what the body actually
returns. The caller read a Boolean as an object pointer (or a string handle) and
crashed on the next use — silently wrong before it is fatal, and it hits the
most ordinary Python there is: a predicate.

Also fixed with it: tuple/list VALUE equality. A tuple lowers to a TPyList, so
`("Options", "Debug") in BOOLEAN_SETTINGS` compared two distinct objects by
IDENTITY and answered False where Python compares element by element
(`PyVarEq` now compares two TPyList payloads element-wise, recursively).

## Fix

`PyInferExprType` answers `tyBoolean` for a depth-0 comparison / membership
operator (`== != < <= > >= in`) or a leading `not`. `and` / `or` are deliberately
NOT included: Python hands back an OPERAND, and NilPy implements that.

## Gate

`test/test_nilpy_membership_bool_return.npy`, CPython-diffed; `make test-nilpy`;
self-host fixedpoint byte-identical.

## Log
- 2026-07-28 — resolved, commit dcbca98c1.

## Resolution

Fixed by dcbca98c1 ("fix(nilpy): return inference must agree between passes").
Re-verified 2026-07-28: the ticket's `is_bool_setting` (a membership test ORed
with another) and `bigger` (a comparison) both return the Boolean CPython does.
The ticket was left in `backlog/` by that commit.
