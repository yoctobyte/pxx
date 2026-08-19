---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`isinstance(x, mod.Class)` is a compile error — `unknown type in isinstance: cabc` — so any code that imports a module and tests against one of its classes must first rebind the class to a bare name."
---

# `isinstance` does not accept a qualified class name

Filed 2026-08-19 from [[feature-b-mimic-collections-abc-mapping-and-mutablemapping]].

Measured on **pinned v356** (`2bb09afb0cff`):

```python
import collections.abc as cabc
print(isinstance({}, cabc.Mapping))
```

| | |
| --- | --- |
| CPython | `True` |
| pxx (pinned v356) | `error: Nil Python: unknown type in isinstance: cabc` |

The diagnostic names `cabc` as the unknown *type*, so the second argument is being
parsed as a bare name and the `.Mapping` selector is not folded in. `from mod
import Cls` then `isinstance(x, Cls)` works — only the qualified form fails.

Ordinary working CPython code uses this spelling constantly, so it is an upward-
compatibility defect, not a dialect choice.

Workaround in `test/lib_mimic_collections_abc.npy`: bind `Mapping = cabc.Mapping`
at module top and test against the bare name. Registered in
`devdocs/dev/track-b-workarounds.md`.
