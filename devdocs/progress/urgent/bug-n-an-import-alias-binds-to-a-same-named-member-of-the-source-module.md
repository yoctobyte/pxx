---
track: N
prio: 85
type: bug
blocked-by: []
summary: "`from M import f as g` binds `g` to M's OWN `g` when the alias name collides with another member of M. `g(1, 5)` returns 18 (M's g) where CPython returns 5 — every argument supplied, no default involved, so this is a pure name-binding defect. Aliasing to a name that is a CLASS in M constructs that class instead. Exit 0, no diagnostic."
---

# An import alias binds to a same-named member of the SOURCE module

- **Type:** bug (name binding) — **Track N** (Nil-Python frontend)
- **Found:** 2026-08-18 by frank2-7e while reproducing
  [[bug-n-a-default-argument-is-dropped-on-every-cross-module-call]]; the
  defaults-free row was pointed out by the coordinator and re-measured here.
- **Measured at:** HEAD, self-host fixedpoint build, differential against
  CPython running the same file unmodified.

## Repro — no defaults involved

`mmod.py`:

```python
def f(a, lo=7):        return lo
def g(a, lo=3, hi=13): return lo + hi
class C:
    def m(self, a, lo=7): return lo
```

```python
from mmod import f as g
print(g(1, 5))      # pxx prints 18   -- CPython prints 5
```

**Every argument is supplied.** No default applies. `18` is `5 + 13`, i.e.
`mmod.g(1, 5)` — the alias bound to the module's own `g` instead of to `f`.

| call | pxx | CPython | |
| --- | --- | --- | --- |
| `from mmod import f as g; g(1, 5)` | **18** | 5 | **DIVERGES — no defaults involved** |
| `from mmod import f as g; g(1)` | **16** | 7 | DIVERGES |
| `from mmod import f as zz; zz(1, 5)` | 5 | 5 | ok — fresh alias name |
| `from mmod import f as C; C(1, 5)` | **a C instance** | 5 | **DIVERGES — constructs M's class** |

The last row is the worst shape: aliasing to a name that is a CLASS in the
source module silently **constructs that class** instead of calling `f`.

## Why this is filed separately from the p90 defaults bug

It is **not** a symptom of
[[bug-n-a-default-argument-is-dropped-on-every-cross-module-call]], and the
top row proves it: all arguments supplied, no default path reached, still
wrong. The two were entangled because the alias ticket's original repro
omitted a default, so both defects fired at once and the crash was read as a
dereferenced dropped default. It is really a call landing on a **different
function with a different signature**.

Filed BEFORE the defaults fix lands, deliberately: once that lands the
fresh-name alias row goes correct while the colliding row stays wrong, and a
reader seeing a half-fixed alias ticket at that moment would mis-diagnose it.

This also means the defaults fix will **not** retire
[[bug-n-calling-through-a-function-alias-with-a-default-omitted-segfaults]] —
that ticket's repro uses a colliding alias name, so its crash is this bug.

## What to check when fixing

`from X import a as b` must bind `b` in the IMPORTING module's namespace only,
to whatever `a` names in X. The alias name must never be looked up as a member
of X. Verify by value against CPython for: an alias colliding with a function
in X, with a class in X, with a variable in X, an alias that shadows a name in
the importing module, and two aliases crossing over
(`from X import a as b, b as a`).
