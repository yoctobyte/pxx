---
track: N
prio: 50
type: bug
---

# `import pkg.sub.mod` does not run pkg/__init__.py

Found 2026-10-20 while testing `__name__`. With `pkg/__init__.py` printing a
line, CPython prints it before `pkg/sub/mod.py`'s output; pxx skips it. Seen on
HEAD before the `__name__` change too. Anything a package's `__init__` sets up
(module-level state, re-exports with side effects) is missing.
