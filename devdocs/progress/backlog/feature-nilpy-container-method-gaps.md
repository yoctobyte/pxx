---
track: N
prio: 40
type: feature
---

# Container-method gaps: `list.remove`, `list.index`, `list.copy`, one-argument `dict.pop`

Found by sweeping every list and dict method against CPython. Everything else
in both sweeps matched exactly — `append`, `pop`, `pop(i)`, `insert`, `count`,
`extend`, `reverse`, `sort`, `clear`, `len`, `get`, `get` with a
default, `dict.copy`, `keys`, `values`, `items`, `setdefault`, `in` — so this is a short,
well-bounded list.

| gap | error |
| --- | --- |
| `x.remove(2)` | `Nil Python: TPyList has no method remove` |
| `x.index(3)` | `Nil Python: TPyList has no method index` |
| `x.copy()` | `Nil Python: TPyList has no method copy` |
| `d.pop("a")` | `Expected: ,, but got:` — a PARSE error |

`d.pop("a", 0)` (two arguments) works and is correct, so the one-argument form
is a signature gap rather than a missing method: the parser requires the
default. In CPython the one-argument form raises KeyError on a missing key and
the two-argument form does not — which is the whole reason both exist.

All three fail loudly at compile time, so nothing silently computes a wrong
answer. Filed as a feature.

`str.index()` is the same shape and is already reported by its own diagnostic
(`unsupported str method .index()`); worth doing in the same pass since
`list.index` and `str.index` share the semantics (raise when absent, unlike
`find`, which returns -1).

## Gate

`make test-nilpy` + self-host byte-identical, plus the list/dict method sweep
diffed against CPython.
