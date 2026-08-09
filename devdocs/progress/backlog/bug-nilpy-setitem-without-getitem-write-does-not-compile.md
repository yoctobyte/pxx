---
track: N
prio: 40
type: bug
---

# `obj[k] = v` does not compile when the class has `__setitem__` but no `__getitem__`

```python
class S:
    def __setitem__(self, k, v):
        self.last = k

s = S()
s["k"] = 1        # error: expected expression
```

CPython runs this: `__setitem__` alone is enough to make a class assignable-into,
and plenty of write-only sinks (recorders, config writers, proxies) declare
exactly that. A compile error, so nothing computes a wrong answer.

Confirmed pre-existing (`stable_linux_amd64/default/pinned` fails identically).

## Same root as the READ half, which is now fixed

`parser.inc`'s subscript arm is gated on `FindUMeth(mci, '__getitem__') >= 0`,
and the `__setitem__` WRITE is handled *inside* that arm. So a class with only
`__setitem__` never reaches its own write path — the gate asks about the getter.

The READ half of this (`bug-nilpy-subscript-read-without-getitem-yields-garbage`)
was fixed 2026-08-09 by giving a getter-less class a run-time TypeError. That
fix deliberately takes over **only a READ**, using the same closing-bracket peek,
and leaves the assignment case exactly as it was — which is why this ticket
exists rather than being silently swept in.

## Fix shape

The arm's condition should be "declares `__getitem__` **or** `__setitem__`", with
the read and write halves inside it each checking for the member they actually
need — the read raising the not-subscriptable TypeError when `__getitem__` is
absent (already implemented), the write raising the same shape when
`__setitem__` is absent. That collapses the gate and the two members into one
place instead of the getter standing in for both.

## Gate

`make test-nilpy` + self-host byte-identical, CPython-diffed over a class with
only `__setitem__` (write then observe the effect), only `__getitem__` (read;
write must raise TypeError), both, and neither — the 2x2, since the current gate
conflates two of those cells.
