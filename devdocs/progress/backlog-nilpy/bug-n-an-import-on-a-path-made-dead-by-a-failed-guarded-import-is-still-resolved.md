---
slug: bug-n-an-import-on-a-path-made-dead-by-a-failed-guarded-import-is-still-resolved
track: N
type: bug
prio: 80
status: backlog
owner: ""
created: 2026-09-10
found-by: frankuser
tags: [nilpy, imports, lekkerzeilen, portability]
blocked-by: []
summary: "`try: import ctypes / except ImportError: return _pxx` followed by `from . import _ctypes_backend` on the fall-through: under pxx the guarded import FAILS, so the fall-through is statically dead, and the compiler resolves it anyway -- `no unit named ctypes and no shim mimic_ctypes`, from a module the program will never reach. This is the LAST wall on lekkerzeilen/platform/__init__.py, the entry point of the priority demo's portability seam, and platform/_pxx.py (the backend that path selects) already COMPILES CLEAN. The bare guarded form works -- `try: import ctypes / except ImportError: ctypes = None` compiles and runs -- so the gap is specifically code DOMINATED by a failed guarded import. That idiom is how every portable Python program selects a backend, so the population is far wider than this one app."
---

# Measured 2026-09-10, compiler `c3e38195d910`, tree `416a8771c`

```
platform/_pxx.py       COMPILES
platform/__init__.py   pascal26:8: error: import: no unit named ctypes and no shim mimic_ctypes
```

`_select_backend()` reads, in substance:

```python
try:
    import ctypes
except ImportError:
    from . import _pxx
    return _pxx, "pxx"
from . import _ctypes_backend      # <- dead under pxx, resolved anyway
return _ctypes_backend, "ctypes"
```

`_ctypes_backend.py:8` is `import ctypes`, unguarded — correctly so, because
nothing reaches it unless ctypes exists.

**Note the reported line: 8, in a file whose line 8 is RST prose.** That is
`bug-n-an-error-inside-an-imported-module-is-reported-with-that-modules-line-number-and-no-file-name`
showing up while diagnosing this one; it cost frankB ten minutes testing whether
a docstring was parsed as an import. Read the line number as belonging to the
imported module.

# What works, so the boundary is stated rather than guessed

| shape | result |
| --- | --- |
| `try: import ctypes / except ImportError: ctypes = None` | **compiles, runs** |
| `from . import _fallback` | **compiles, runs** |
| the fall-through above | `no unit named ctypes` |

So this is not "guarded imports do not work". It is: **the compiler resolves
imports on a path the failed guard has already made unreachable.**

# Why it is 80

It is the last wall on the seam ENTRY of the prio-90 target, and the backend it
selects already compiles. Nothing above `platform/` can run until `__init__.py`
does — and the fix is not a `mimic_ctypes`, which is settled: the seam exists
precisely so ctypes is never needed under pxx, and shimming it would make the
seam pointless.

The wider population is the reason it is not merely a lekkerzeilen ticket:
`try: import X / except ImportError: <use fallback>` is the standard Python
portability idiom, and any program using it to avoid a module we do not have
hits this.
