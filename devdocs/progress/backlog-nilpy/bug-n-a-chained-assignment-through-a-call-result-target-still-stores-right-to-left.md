---
slug: bug-n-a-chained-assignment-through-a-call-result-target-still-stores-right-to-left
track: N
prio: 25
type: bug
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [nilpy, parser, assignment, evaluation-order, silent]
blocked-by: []
summary: "`box(1)[idx(\"i\")] = box(2)[idx(\"j\")] = 7` evaluates its target subexpressions in the wrong order and prints the right values, so nothing can see it. Measured 2026-09-10 against the FIXED chain arm: pxx gives `[1, 2, 'j', 'i']` where CPython gives `[1, 'i', 2, 'j']`, and both stores land. This is the NAMED RESIDUAL of bug-n-a-chained-assignment-to-two-attributes-does-not-parse, which put every target shape whose receiver is a NAME onto one left-to-right arm; a target whose receiver is a CALL is not one of those shapes, so it still falls through to PyParseLValueAST's nested right-associative reading. Ranked low deliberately, not because the divergence is small but because a chain whose targets are call results is not a shape any corpus here writes -- one measured instance, written by hand to find the boundary. What makes it worth a row at all is that it is SILENT: the values are right and only the side effects of the target subexpressions differ, which is the same property that let the general case sit unreported."
---

# The measurement

```python
order = []
def idx(tag):
    order.append(tag)
    return 0
def box(w):
    order.append(w)
    return [0, 0]
box(1)[idx("i")] = box(2)[idx("j")] = 7
print(order)
```

| | `order` |
| --- | --- |
| CPython | `[1, 'i', 2, 'j']` |
| pxx (compiler `defccc38ad3e`) | `[1, 2, 'j', 'i']` |

Both stores happen and both hold 7. Only the ORDER of the receivers and index
expressions differs, so no value assertion can observe it.

# Why it is left open rather than folded into the fix

`PyChainAssignAhead` admits a target only when it is a token run this parser
can store into without a trial parse: `NAME`, `NAME.field`, either followed by
`[...]` groups — exactly the set `PyParseUnpackAssign` collects. A call-result
receiver is not in that set, so the statement keeps the arm it has today.

Widening the lookahead is not the fix. The receiver grammar is the other
mechanism's — see
[[bug-n-a-subscript-store-whose-receiver-is-a-call-result-does-not-parse]] —
and the honest shape of the work is that a chained assignment should be able to
ask ONE lvalue parser for each of its targets, rather than a token lookahead
guessing which shapes that parser will accept. That is the same
`normalise-dont-special-case` argument that produced the fix above; this row is
what is left of the second path.

# What a fix must carry

The ORDER probe, not a value assertion. A test that only checks `7 7` passes on
the broken compiler.
