---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`self[k]` written inside a base-class method binds to that class's own __getitem__ instead of the subclass override, so a mixin written the natural way raises the base's KeyError. Sibling arm of the already-fixed bug-n-a-builtin-subclass-subscript-operator-skips-the-override."
---

# A subscript inside a base class skips the subclass override

Filed 2026-08-19 from [[feature-b-mimic-collections-abc-mapping-and-mutablemapping]].

Measured on **pinned v356** (`2bb09afb0cff`):

```python
class Base:
    def __getitem__(self, k):
        raise KeyError(k)
    def fetch(self, k):
        return self[k]          # <-- binds to Base.__getitem__
class Sub(Base):
    def __getitem__(self, k):
        return 'val-' + k
print(Sub().fetch('x'))
```

| | |
| --- | --- |
| CPython | `val-x` |
| pxx (pinned v356) | `Unhandled exception: KeyError: 'x'` |

`self.__getitem__(k)` spelled explicitly **does** dispatch correctly — only the
`[]` operator form is statically bound. That asymmetry is the bug: two mechanisms
serve one concept and only one of them is virtual.

Sibling arm of
[[bug-n-a-mixin-cannot-iterate-self-and-an-abstract-iter-breaks-its-overrides]]
(same defect via `for x in self`) and of the already-resolved
`bug-n-a-builtin-subclass-subscript-operator-skips-the-override`, which fixed the
builtin-base arm of the same double case without the user-base arm. Third sighting
of one root cause — `devdocs/dev/root-cause-over-microfix.md` says that is a design
flaw, not three bugs.

Track B workaround: `lib/rtl/mimic_collections_abc.py` spells every internal
subscript `self.__getitem__(k)`. Registered in
`devdocs/dev/track-b-workarounds.md`.
