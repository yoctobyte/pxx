---
slug: feature-n-a-class-statement-inside-a-def-is-refused
title: a class statement inside a def is refused
summary: >
  `def make(): class P: ...` fails at compile time with `expected expression`
  on the `class` keyword. A function-local class (a factory, a test fixture, a
  one-off exception type inside a test) has no lowering at all. It is a clean
  refusal, not a wrong value, but the message does not say what is missing.
track: N
type: feature
prio: 30
owner: unassigned
status: open
status-note: "2026-11-11: the refusal now names the construct (test_nilpy_a_class_statement_inside_a_def_is_refused_fail.py); the lowering is still open."
---

## Repro (2026-11-11, wt2 tree based on 1c6f046ff4)

```python
def make():
    class P:
        def __init__(self, v):
            self.v = v
    return P(3)
print(make().v)        # CPython: 3
```

```
pascal26:2: error: expected expression
  near: make ( ) :   >>> class P :
```

Found while writing a leak probe: `def f(): class E(Exception): pass` inside a
test helper, which is the most common real use (lekkerzeilen's `tests/` has
several, per bug-n-a-nested-class-is-hoisted-to-module-scope-and-is-not-an-
attribute-of-its-enclosing-class).

## Notes

- A nested class in a CLASS body is hoisted to module scope (the ticket named
  above). The cheapest route here is the same hoist: register the class at
  module level under a hidden unique name, and bind the local name to the
  class reference inside the def. That is wrong only when the class body reads
  the def's locals or when two calls must produce distinct class objects. Both
  are rare and could be refused by name.
- Until then, at least the message should name the construct ("a class
  statement inside a def is not supported; move it to module level") rather
  than "expected expression".
