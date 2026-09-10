---
slug: bug-n-a-module-bound-by-an-import-is-not-a-value
track: N
type: bug
prio: 75
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [nilpy, imports, lekkerzeilen, values]
blocked-by: []
summary: "`from . import two` then `return two, \"pxx\"` -> `undefined variable (two)`. The module BINDS and `two.B` reads correctly; what fails is the bare name in VALUE position. A pxx module is a UNIT and a unit is not a first-class value, so there is nothing to push. This is the wall immediately behind bug-n-an-import-on-a-path-made-dead-by-a-failed-guarded-import-is-still-resolved on lekkerzeilen/platform/__init__.py, whose seam returns the selected backend AS A VALUE (`return _pxx, \"pxx\"`) and then reads members off the variable holding it (`gl = _backend.gl`). Both halves are needed and the second is the larger: a variable holding a module has no type today that an attribute lookup could resolve against."
---

# Measured 2026-09-10, compiler `ca814b0aabcc`, tree at `5fb6e3d57` + the dead-path fix

Minimal, and it is minimal on purpose — the package, the relative spelling and
the `try` are all removable without changing the answer:

```python
# dotpkg/__init__.py
def sel():
    from . import two
    return two, "pxx"        # <- pascal26:6: error: undefined variable (two)
```

```
near: . import two  return two >>> , "pxx"
```

lekkerzeilen/platform/__init__.py:95 is the same three tokens:

```
near: . import _pxx  return _pxx >>> , "pxx"
```

# The boundary, measured rather than guessed

| shape | result |
| --- | --- |
| `from . import two` at module level, then `two.B` | **works** |
| `from . import two` inside a def, then `two.B` | **works** |
| `from nilpy_relpkg import two`, either position, then `two.B` | **works** |
| `from . import two`, then bare `two` as a value | `undefined variable` |

So this is not about relative imports, not about packages, and not about
position. **The binding exists; it just is not a value.** Every row above but
the last was checked, which is what rules out the three explanations the error
text invites.

# Why this is two features and the second is the bigger one

The seam does both halves and neither is useful alone:

```python
_backend, _backend_name = _select_backend()   # 1. a module AS a value
gl = _backend.gl                              # 2. a member THROUGH a variable
open_window = _backend.open_window
```

1. **A module as a value.** A pxx module is a UNIT — a compile-time namespace,
   not an object — so there is no runtime thing for `return two` to push. It
   needs a module-object value, and the obvious cheap shape (a record or a
   handle naming the unit index) is only cheap until (2).

2. **A member read through a VARIABLE holding a module.** `_backend.gl` cannot
   be resolved the way `two.B` is, because `two` is a name the compiler resolves
   to a unit at parse time and `_backend` is a local whose value is not known
   until run time. That is open-world dispatch over units, and the existing
   `qualifier` door (`no member X came of the qualifier Y`) is entirely
   compile-time.

**Do not fix (1) alone.** It would make `return _pxx, "pxx"` compile and leave
`_backend.gl` to fail one line later with a different message, which is the
shape this repo keeps paying for — see the class-scope pair on 2026-09-10, where
repairing one door of two left the two disagreeing in a NEW way.

# What is NOT wanted

A special case for `return <module>` that re-resolves the name at the call site.
It would make the demo's line 100 work and would answer wrongly the moment a
module value crosses a real boundary — stored in a list, passed as an argument,
chosen by a conditional. The corpus writes all three (`_backend` is a module
global read from four other modules).

# Provenance

Found by clearing the wall in front of it. That ticket claimed to be "the LAST
wall on platform/__init__.py"; it was not, and the census could not have said so
— a first-failure census reports one error per subject and everything behind it
is invisible. Modules-compiling delta from clearing it: **0**, predicted before
the re-run and matched.
