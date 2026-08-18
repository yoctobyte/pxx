---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`import sys` works and `from sys import version_info` does not — `error: import: no unit named sys and no shim mimic_sys`. Same for `os`. The from-import path does not consult whatever table the plain-import path resolves builtin modules through; `math`, `time` and the mimic_ shims resolve either way, so it is these compiler-provided modules specifically. One corpus file (html5lib/_tokenizer.py) stops here."
status: working
owner: frank2-7e
---

# `from sys import X` fails while `import sys` works

- **Type:** bug — **Track N** (Nil-Python frontend, import resolution).
- **Found:** 2026-08-18 by frank3-fc while ranking the shim rows of
  [[feature-b-module-shims-for-the-html5lib-corpus]].
- **Measured against:** `pinned` **v347** (`f5da30bc9`).
- CPython accepts and runs both spellings, so this is a defect.

## Repro

```python
import sys              # ok
from sys import argv    # error: import: no unit named sys and no shim mimic_sys
```

## The boundary

| import | result |
| --- | --- |
| `import sys` | OK |
| `from sys import argv` / `version_info` | **error: no unit named sys** |
| `import os` | OK |
| `from os import getcwd` | **error: no unit named os** |
| `from math import pi` | OK |
| `from time import time` | OK |
| `from six import text_type` (a `mimic_` shim) | OK |

So the from-import path resolves `.py` shims and whatever provides `math` and
`time` perfectly well. What it does not resolve is the set that `sys` and `os`
belong to — the modules the compiler provides directly. Whichever table the
plain-import path consults for those, the from-import path is not consulting
it. (Hypothesis, not measured: nothing here read the resolver.)

## Do NOT close this by writing a mimic_sys.py

That was the first thing that came to mind and it is the wrong fix twice over:
`sys` is already provided — it would be a second, competing `sys` — and it
would hide the resolver gap rather than close it, which is what
`devdocs/dev/normalise-dont-special-case.md` is about. The two import spellings
are two shapes of one concept; the fix belongs where they diverge.

## What it costs today

`html5lib/_tokenizer.py` does `from sys import version_info` and stops there —
one row of the ladder table (`missing module: sys`), on the file that is the
tokenizer.

Related, and probably the same fault line: `sys.version_info` COMPILES and then
raises at runtime with an explicit "this build has no sys.version_info: the
import it came from could not be resolved" — so someone has already met the
resolver gap from the other side and put a loud failure there rather than
closing it.
