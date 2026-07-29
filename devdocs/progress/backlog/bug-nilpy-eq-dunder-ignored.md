---
track: N
prio: 70
type: bug
---

# `__eq__` is ignored — `==` on user objects compares identity

```python
class V:
    def __init__(self, v: int):
        self.v = v
    def __eq__(self, o) -> bool:
        return self.v == o.v

print(V(1) == V(1))   # CPython: True    pxx: False
print(V(1) != V(1))   # CPython: False   pxx: True
```

`==` falls through to a pointer comparison and never calls the user's
`__eq__`. `!=` is wrong in the same way, from the same cause.

Silent, and the failure direction is the bad one: two equal values report
unequal, so a membership test, a dedup or an `if got == expected` quietly takes
the wrong branch instead of failing loudly.

`__lt__` and `__len__` DO dispatch (`a < b` and `len(a)` are both correct), so
the operator-to-dunder machinery exists and `__eq__`/`__ne__` are simply not
wired into it.

Related but distinct: dict value equality is also identity-based
([[bug-nilpy-dict-equality-compares-identity]]). Together they mean `==` is
untrustworthy for every compound value that is not a list.

Found by the OOP sweep against CPython.

## Gate

`make test-nilpy` + self-host byte-identical, plus `==`/`!=` on a class with
`__eq__`, one without, across an inheritance pair, and against None.
