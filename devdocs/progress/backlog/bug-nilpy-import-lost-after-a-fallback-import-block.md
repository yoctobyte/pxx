---
track: N
prio: 65
type: bug
---

# A later `import X` stops being a usable qualifier after a fallback-import block

songformatter's `convertrawtext.py` opens with two `try: <import> except
ImportError:` blocks (reportlab, then PIL) and then a plain block of imports —
`import os`, `import atexit`, `import tempfile`, ... After that, a qualified call
on one of them fails to parse:

```
pascal26:97: error: unexpected token
  near: name     atexit >>>  register
Expected: =, but got:  (Kind: 81, Line: 97)
```

`atexit` is not recognised as a unit qualifier, so `atexit.register(del_tmp_file)`
is read as an assignment target and the parser wants an `=`.

## Repro

The first 52 lines of `convertrawtext.py` (its import section, nothing else) plus

```python
def bye():
    print("bye")

atexit.register(bye)
```

is enough. The same call compiles and RUNS in isolation, with and without
`import tkinter as tk` alongside it, so it is the import section as a whole, not
`atexit`.

## Ruled out

- Not the submodule-alias registration added with dotted imports: disabling that
  hunk changes nothing.
- Not `atexit` itself, and not the presence of tkinter.

## Suspicion

`PyPreScanImports` walks top-level tokens counting INDENT/DEDENT to stay at depth
0. The fallback-import handler consumes its blocks with its own skipping
(`PySkipRestOfBlock` / `PySkipIndentedBlock`), so a block whose imports were
decided at compile time may leave the pre-scan's idea of depth — or the token
positions it scans — out of step with the body parse, and imports after it are
registered in one pass but not the other. Start by dumping which units
`PyPreScanImports` registers for this file versus which the body parse sees.

## Gate

`make test-nilpy` plus a `.npy` with a fallback-import block followed by a plain
import that is then used through a qualifier.
