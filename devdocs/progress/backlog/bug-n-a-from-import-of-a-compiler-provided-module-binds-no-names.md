---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`from sys import argv` now resolves but binds nothing — a bare `argv` is `undefined variable` while `sys.argv` works. Consuming a from-import of a compiler-provided root (sys, os, textwrap, select, typing, itertools, dataclasses, __future__) discards the names it publishes, so the spelling CPython programs actually use is the one that does not work. General across all eight roots."
---

# `from X import n` of a compiler-provided module binds no names

- **Type:** bug — **Track N**. **Found:** 2026-08-18 by frank2-7e, closing
  [[bug-n-from-sys-import-fails-while-import-sys-works]].
- **Measured at:** HEAD `7e7ed35d7`.

## Repro

```python
import sys
print(len(sys.argv))      # works -> 1

from sys import argv
print(len(argv))          # error: undefined variable (argv)
```

CPython accepts and runs both, so by NilPy's upward-compatibility rule this is a
defect, not a dialect choice.

## Why it looks like a regression and is not

The resolver fix above stopped `from sys import argv` failing at the IMPORT. It
did not make the import *do* anything: these roots are consumed-only, which
means the names are parsed and dropped. So the failure moved from the import
line to the use site. That is the intended policy for a root with no backing
unit — an unsupported name must wall visibly — but it is wrong for a name the
compiler **does** provide, and `argv` is one.

## Shape of the fix

The qualified path already resolves these members (`pyparser.inc`, `nm = 'argv'`
under the sys handling). So the from-spelling needs to bind the imported name to
the same member access the qualified spelling produces — an alias from the bare
name to `(root, member)` — rather than discarding it. Then a name the compiler
provides works both ways, and a name it does not still walls at its use site,
which is the behaviour the consumed-only policy is actually after.

Affects all eight no-backing-unit roots, not just `sys`.

## Do NOT close this with a mimic_sys

Same reason the parent ticket gives: `sys` is compiler-provided, so a shim would
be a second competing `sys`. The fix is in the binding, not in a new module.
