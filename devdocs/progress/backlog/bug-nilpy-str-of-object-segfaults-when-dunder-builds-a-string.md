---
track: N
prio: 75
type: bug
---

# `str(obj)` SEGFAULTS when `__str__`/`__repr__` builds a string and nothing touched the instance first

```python
class V:
    def __init__(self, v: int):
        self.v = v
    def __str__(self) -> str:
        return "A(" + str(self.v) + ")"

a = V(1)
print(str(a))          # CPython: A(1)     pxx: SIGSEGV
```

Seven lines. `__repr__` in place of `__str__` behaves identically.

## What it is NOT — two wrong leads, both measured out

The first reading was "`__repr__` is unimplemented". It is implemented:
PyStrOfValue falls back to `__repr__` when `__str__` is absent, and a
`__repr__` returning a LITERAL prints correctly. The second reading was
"`str(self.v)` inside the dunder recurses". It does not — the gdb backtrace is
two frames deep, and replacing `str(self.v)` with a local (`n = self.v; ...
str(n)`) crashes identically.

## What it actually depends on

| program | result |
| --- | --- |
| `__str__` returns a LITERAL (`return "S"`) | works |
| `__str__` returns a CONCATENATION | **SIGSEGV** |
| same body, method named `show()`, called as `a.show()` | works |
| `print(a.v)` on the line BEFORE `print(str(a))` | **works** |
| a class with more methods around it (`get`, `__eq__`) | works |

So it needs all of: dispatch through `str(obj)` (not a direct method call), a
managed — i.e. built, not literal — result, and no earlier statement touching
the instance. Crash is inside `V.__str__ + 0x50` itself, per the `.map`.

That combination is the signature of an uninitialised managed Result slot: the
slot holds stack garbage, the first assignment RELEASES that wild handle, and
any preceding statement changes what garbage is there — which is exactly why
adding an unrelated `print(a.v)` "fixes" it. Same shape as the already-fixed
`bug-nilpy-method-returning-str-garbage`, and the note in
[[project_nilpy_method_result_not_zeroed_landmine]] (a method Result reached
through the class PRE-PASS is registered skGlobal, and skLocal is what gates
the prologue zero-init) says where to look first.

Very likely the SAME root as
[[bug-nilpy-method-returning-a-fresh-string-leaks]], where the method path's
`$pyresult` is a managed slot that gets a raw `store_sym` of a frozen string
instead of an ARC assign. Check that first: one fix may close both.

Found by the OOP sweep against CPython.

## Gate

`make test-nilpy` + self-host byte-identical, plus `str()`/`print()`/`format()`
of an object whose `__str__` and/or `__repr__` builds a string, as the FIRST
statement touching the instance.
