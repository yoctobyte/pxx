---
track: N
prio: 70
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

---

## Coordinator verification 2026-08-18 — the segfault is the LUCKY case. Silent wrong values.

Verified at **HEAD** (`bd047aba6`, self-host fixedpoint) as well as pinned v347, so this
is not pin-only: the six-line repro segfaults on both. But varying the shape moved the
boundary somewhere much worse than the title says.

**The trigger is not "a default is omitted". It is "an omitted default is READ".**

| shape (alias call, args omitted) | result |
| --- | --- |
| 1 default, omitted, **not used** in body | ok |
| 2 defaults, omitted, **not used** in body | ok |
| 1 default, omitted, **read** in body | **returns 3 where the direct call returns 1** |
| 2 defaults, omitted, **read** in body | **SIGSEGV** |
| all arguments supplied (alias) | ok |
| defaults omitted, called **directly** (no alias) | ok |

The third row is the important one and it is not in the ticket above:

```python
def r(a, x, lo=0):
    return lo + 1

ali = r
print(ali([1, 2], 2))   # alias  -> 3      WRONG
print(r([1, 2], 2))     # direct -> 1      correct (CPython: 1)
```

**Exit 0, no diagnostic, plausible number.** So the defaulted parameter's value is never
materialised at the alias call site and the body reads whatever occupies the slot. With
one default the garbage happens to be arithmetically usable and you get a wrong answer;
with two, it is dereferenced and you get the crash. **The crash is the detectable case.**

This is the failure mode this repo treats as the expensive one — a plausible wrong value
far from the cause — so re-prioritised **65 → 70**. A segfault stops a build; this
silently changes results. `bisect_left` vs `bisect_right` on a run of equal elements is
exactly a "lo/hi defaulted and read" shape, and getting a wrong index back rather than a
crash is how it would reach a caller.

**Do not close this on the segfault alone.** The regression test must assert the
RETURNED VALUE of an alias call that omits a read default, against the direct call's
value — a test that only checks "does not crash" passes on the one-default shape while
it is still wrong.

Found by varying the shape after a simpler four-line version of the reported repro
PASSED — worth recording, because that near-miss would have read as "cannot reproduce"
and bounced the ticket.
