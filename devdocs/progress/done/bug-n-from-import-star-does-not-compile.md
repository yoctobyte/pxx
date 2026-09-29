---
track: N
prio: 20
type: bug
blocked-by: []
status: done
found-by: frankuser (2026-09-29; `from tkinter import *` and MicroPython's `from machine import *`)
tags: [nilpy, import, parser]
summary: "`from X import *` failed with \"expected expression\" for every module, `from math import *` included. It now compiles. X's names already resolve through flat unit scope. What a star import adds is 8878f1ea97's per-name record for public names a builtin also has, so the importer's bare `len` or `max` reaches X's def. The names are X's __all__ if it defines one, else its top-level names not starting with `_`. Call-table members (random, sys, os.path) are not bound by `*`; see the LOGBOOK."
owner: ""
---

# `from X import *` does not compile

```python
from math import *     # v451: error: expected expression
```

## Fix (compiler/pyparser.inc)

- The from-import name loops accept `*`: the unit arm and the consumed-only
  arm (typing, collections, itertools...).
- `PyNoteTopName` runs before each top-level statement of an imported
  module and consumes nothing. It notes the name a `def`, `class` or
  `NAME =` binds, when a builtin has that name, and the string items of
  `__all__ = [...]` / `(...)`.
- `PyStarImportRecord` then records those names for the importing unit,
  exactly as a `from X import len` does (8878f1ea97's `PyImpName`):
  - from `__all__` when X defines one;
  - otherwise the names not starting with `_`.
  A builtin X does not export stays the builtin.

## Measured (2026-09-29)

- `test/test_nilpy_from_import_star.npy`, with helpers
  `test/starmod_plain.py` and `test/starmod_all.py`, covers:
  - `from math import *`;
  - a user module's function, value and class, with its `len` shadowing the
    builtin;
  - an `__all__` module whose listed `max` shadows the builtin and whose
    unlisted `sum` does not.

  It equals CPython on x86-64, i386 and wasm32. The previous compiler
  refuses it on all three. Those three are the rows.
- Probes that equal CPython: `from typing import *`, `from collections
  import *` (Counter), `from tkinter import *` (compile and bind), a
  builtin-named class, and `import m` still not leaking m's `sum`.
- Differential over the 472 tracked NilPy tests that import something,
  compiled and run with the compiler before and after: identical output and
  exit code for all 472. The note runs at every imported module's top level,
  which is why the quick tier was not enough.

## Not covered (LOGBOOK)

- Members the compiler provides by call table rather than by a unit
  (`random.seed`, `sys.argv`, `os.path.basename`, `itertools.count`) are not
  bound by `*`. Their use sites fail at compile time with "undefined
  variable". PyStdlibCallProc is an if/else chain; making it a table that a
  star import can walk is the fix.
- A name X does not export (`_hidden`, or one left out of `__all__`) is
  still reachable through flat unit scope, where CPython raises NameError.
  A named from-import has the same difference.
