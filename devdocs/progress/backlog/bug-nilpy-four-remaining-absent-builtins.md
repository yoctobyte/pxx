---
track: N
prio: 20
type: bug
blocked-by: []
summary: "The residue of the 2026-08-12 builtin sweep: `slice`, `dir`, `vars`, `memoryview` are `undefined variable`, and `complex` is a numeric TYPE this dialect does not have rather than a missing name. None has appeared in any corpus scan."
---

# Four absent builtins, and one that is not a builtin

Re-filed from [[bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep]]
when that ticket closed. It turned one sweep into eleven landed builtins; this
is what nobody reached for.

| name | status | note |
| --- | --- | --- |
| `slice(1, 3)` | `undefined variable (slice)` | the slicing SYNTAX works fully; only the object is missing |
| `dir(x)` | `undefined variable (dir)` | RTTI has the members — this is a listing, not new information |
| `vars()` | `undefined variable (vars)` | wants a real `__dict__`, which instances do not have |
| `memoryview(b)` | `undefined variable (memoryview)` | a zero-copy view over TPyBytes |
| `complex(1, 2)` | no complex TYPE at all | **not a missing builtin** — see below |

## `complex` is a feature, not a name

The other four are routines with nowhere to live. `complex` is a numeric type
this dialect does not have: adding the name without the arithmetic, the repr,
the `.real`/`.imag` and the coercion rules would be worse than its absence. If
anyone wants it, it is its own feature ticket, not a row here.

## Why this is prio 20

Measured across the html5lib ladder (`webencodings`, `tinycss2`, `html5lib`, 58
files) and the earlier corpus scans: **none of these names appears as a wall**.
They are here so the sweep's record is complete, not because anything is blocked.
Take them if one turns up in a real program — that is the signal this list is
waiting for.

## Gate

Per name as it lands: a `.npy` diffed against CPython, plus a row asserting a
user `def slice` / `def dir` still shadows the builtin, which is Python's rule
and the pattern every intercept in this family already follows.
