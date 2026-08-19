---
track: N
prio: 55
type: bug
blocked-by: []
summary: "A base class whose __iter__ only raises poisons every subclass override: `for k in self` inside a base method calls the BASE __iter__, and the subclass's real __iter__ is never reached — `iter() returned non-iterator of type 'Sub'`. This is the whole ABC mixin pattern."
---

# A mixin cannot iterate `self`, and an abstract `__iter__` breaks its overrides

Filed 2026-08-19 from [[feature-b-mimic-collections-abc-mapping-and-mutablemapping]],
which is exactly this pattern: `Mapping` stores nothing and its entire value is
mixins that dispatch *down* into the subclass.

Measured on **pinned v356** (`2bb09afb0cff`):

```python
class Base:
    def __iter__(self):
        raise NotImplementedError('abstract')
    def keys(self):
        out = []
        for k in self:          # <-- binds to Base.__iter__, not Sub's
            out.append(k)
        return out
class Sub(Base):
    def __iter__(self):
        return iter(['a', 'b'])
print(Sub().keys())
```

| | |
| --- | --- |
| CPython | `['a', 'b']` |
| pxx (pinned v356) | `Unhandled exception: TypeError: iter() returned non-iterator of type 'Sub'` |

The error message is the tell: it reports `Sub` as the non-iterator, i.e. the
`for` lowering resolved `__iter__` **statically to the declaring class** and then
fell back to treating `self` itself as the iterator. The subclass override is
never consulted.

Sibling arm of [[bug-n-a-subscript-inside-a-base-class-skips-the-subclass-override]]
— same defect, different operator (`for x in self` vs `self[k]`). Per
`devdocs/dev/normalise-dont-special-case.md`, fix both arms together and grep for
a third (`len(self)`, `self.__contains__`, `repr(self)`).

Track B workaround in place (`lib/rtl/mimic_collections_abc.py`): every mixin
takes its keys via `self.keys()` rather than iterating `self`, and each abstract
method ends with a dead `return iter([])` after the `raise` so the return type is
inferrable. Registered in `devdocs/dev/track-b-workarounds.md`; revert when this
closes.
