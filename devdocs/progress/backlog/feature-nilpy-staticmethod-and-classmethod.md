---
track: N
prio: 35
type: feature
---

# `@staticmethod` and `@classmethod` are rejected

```python
class C:
    @staticmethod
    def s(a: int) -> int:
        return a + 1
```

```
error: Nil Python: unsupported decorator inside class (only ...)
```

A compile error, so nothing computes a wrong answer. `@property` already works,
and `@dataclass` works, so the decorator machinery is there and this is two more
cases.

`@classmethod` needs the metaclass `cls` receiver, which pxx already has
([[project_fpcunit_green_metaclass_self]] — Self as a runtime metaclass hidden
argument); `@staticmethod` is the easy one, a plain proc with no receiver.

Found by the OOP sweep against CPython — dataclasses (including a defaulted
field), `@property`, inheritance and `super()` all matched exactly.

## Gate

`make test-nilpy` + self-host byte-identical, plus a static method and a class
method called through the class and through an instance, and a class method in
a subclass.
