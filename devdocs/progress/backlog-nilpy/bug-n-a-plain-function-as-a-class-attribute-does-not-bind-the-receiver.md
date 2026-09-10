---
slug: bug-n-a-plain-function-as-a-class-attribute-does-not-bind-the-receiver
track: N
prio: 40
type: bug
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [nilpy, classes, descriptors, staticmethod]
blocked-by: []
summary: "`class C: plain = two` then `c.plain(7)` on an INSTANCE does not pass the instance. CPython's plain-function-becomes-method rule binds it -- `def two(a, b)` reached as `c.plain(7)` gets `a = the C instance, b = 7` and prints `a=C b=7` -- and we raise `TypeError: missing 1 required positional argument(s)`. Loud rather than silent, which is the good direction, and a real divergence on an idiom people write. Found 2026-09-10 while landing bug-n-staticmethod-is-not-a-value: the unwrapped `plain = f` row was going to be that fix's CONTROL, and CPython's own oracle refused it -- which is the point, since binding the receiver is exactly the rule `staticmethod` exists in the language to opt OUT of. Read through the CLASS (`C.plain(7)`) the two agree, so the divergence is the instance door only. NOT the same as bug-n-a-staticmethod-read-through-an-instance-binds-a-receiver (p25), which is about `type(k.stat).__name__` on a DECORATED method: that one binds where it should not, this one fails to bind where it should."
---

# Measured 2026-09-10, compiler `98b6545b4652`

```python
def two(a, b):
    return "a=%s b=%s" % (type(a).__name__, b)

class C:
    plain = two

c = C()
print(c.plain(7))
```

| | |
| --- | --- |
| CPython | `a=C b=7` |
| pxx | `Unhandled exception: TypeError: missing 1 required positional argument(s)` |

`C.plain(7)` — through the class rather than an instance — agrees in both.

# Why it is worth recording rather than leaving implicit

It is the reason `staticmethod` exists at all. A reader of
`test/test_nilpy_staticmethod_as_a_value.npy` will ask why the unwrapped
control is only exercised through the class, and this is the answer; the test's
header says so and points here. Asserting the instance row against a
CPython-generated oracle would be a row that is red by construction, which is
why it is filed rather than tested.

# Not a wrong ANSWER, and that matters for the ranking

We refuse where CPython succeeds, with a message naming the arity. Nothing
computes a wrong value, and nobody gets a silently mis-shifted argument list.
That is what puts it at 40 rather than higher — it fails the way a missing
feature should fail.
