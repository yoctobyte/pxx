---
track: N
prio: 75
type: bug
---

# Defining `__repr__` makes `str(obj)` SEGFAULT

```python
class V:
    def __init__(self, v: int):
        self.v = v
    def __repr__(self) -> str:
        return "R" + str(self.v)

print(str(V(1)))      # CPython: R1      pxx: SIGSEGV
```

Six lines. It crashes whether or not `__str__` is ALSO defined — with both
present CPython prints the `__str__` result (`V1`) and pxx still crashes, so
`__repr__` is not merely unimplemented: its presence breaks the `__str__` path
too.

`__lt__` and `__len__` dispatch correctly (`a < b`, `len(a)`), so the dunder
machinery works in general and this is specific to `__repr__` — most likely a
table entry that is registered but resolves to nothing callable, in which case
[[project_bodyless_procaddr_links_to_entry_minus_one]] is the shape to check
first.

`__repr__` is not exotic: it is the standard way to make objects printable in
a debugger and in collection output, and defining it should never crash.

Found while sweeping OOP constructs against CPython (inheritance, `super()`,
`isinstance`, class attributes, aliasing, `hasattr`, comprehension over
objects) — the rest of that sweep matched exactly.

## Gate

`make test-nilpy` + self-host byte-identical, plus a dunder table test:
`__str__`, `__repr__`, both together, and neither, each through `str()`,
`print()` and `"{}".format()`.
