---
track: N
prio: 65
type: bug
blocked-by: []
summary: "A call through a module-level function ALIAS that omits a defaulted parameter segfaults at runtime, with no diagnostic at compile time. `f = g` then `f(a, b)` where g is `def g(a, b, lo=0, hi=-1)` crashes; the same call with all four arguments supplied is fine, and calling `g` directly with the defaults omitted is fine. Six-line repro, no imports involved."
---

# Calling through a function alias with a default omitted segfaults

- **Type:** bug — **Track N** (Nil-Python frontend / lowering).
- **Found:** 2026-08-18 by frank3-fc, while writing `lib/rtl/mimic_bisect.py`
  for [[feature-b-module-shims-for-the-html5lib-corpus]].
- **Measured against:** `pinned` **v347** (`f5da30bc9`).
- **CPython accepts and runs this**, so it is a defect and not a dialect
  choice — `bisect = bisect_right` is a line in CPython's own `Lib/bisect.py`.

## Repro

Six lines, one file, no imports:

```python
def real(a, x, lo=0, hi=-1):
    if hi < 0:
        hi = len(a)
    return hi - lo

ali = real
print(ali([1, 2, 2, 3], 2))
```

```
$ pinned t.npy /tmp/t && /tmp/t
ok: /tmp/t  [code=2335086B ...]
Segmentation fault (core dumped)
```

It **compiles clean** — no warning, no note. CPython prints `4`.

## The boundary, one variable at a time

| shape | result |
| --- | --- |
| `ali([1,2,2,3], 2)` — alias, defaults omitted | **segfault** |
| `ali([1,2,2,3], 2, 0, 4)` — alias, defaults supplied | 4 (correct) |
| `real([1,2,2,3], 2)` — direct, defaults omitted | 4 (correct) |
| alias of a function with **no** defaulted parameters | correct |
| same, with the alias in an imported module (`from m import ali`) | **segfault** |
| same, all in one file, no import at all | **segfault** |

So it is neither about imports nor about aliases generally: it is specifically
**an alias plus an omitted default**. The reading that fits every row is that
the alias binds the callee's entry point but not its default-argument
metadata, so the call site passes 2 arguments to a body that reads 4 and the
missing two are whatever the stack held. That paragraph is a hypothesis, not a
measurement — nothing here inspected the lowering.

## Why this is worth a p65

It is a **crash with no diagnostic**, and the shape is not exotic: aliasing a
function is how Python modules ship legacy spellings, and defaulted parameters
are how they ship optional arguments. `bisect` is precisely both at once, which
is how this was found — the stdlib module the corpus imports has
`bisect = bisect_right` in it.

Worse, the two ingredients are separately fine, so a caller who tests the alias
with all arguments supplied sees it work and concludes the alias is sound.

## Effect on Track B today

`lib/rtl/mimic_bisect.py` ships the platonic `bisect = bisect_right` and
`insort = insort_right` aliases (they are part of the module's real API).
`test/lib_mimic_bisect.npy` therefore exercises them only with every argument
supplied, and says so at the call site. When this lands, drop that restriction
and let the test call `bisect(r, 2)` the way a caller would.
