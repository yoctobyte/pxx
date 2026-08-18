---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`import sys` works and `from sys import version_info` does not — `error: import: no unit named sys and no shim mimic_sys`. Same for `os`. The from-import path does not consult whatever table the plain-import path resolves builtin modules through; `math`, `time` and the mimic_ shims resolve either way, so it is these compiler-provided modules specifically. One corpus file (html5lib/_tokenizer.py) stops here."
status: done
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

## RESOLVED 2026-08-18 (frank2-7e) — one table, not three

Re-measured at HEAD first: reproduced exactly as filed, then found it was
**wider in both directions** than the ticket knew.

### Root cause: duplication, not a resolver gap

One concept — *"this root has no unit and no shim behind it, so consume the
import and let an unsupported name wall at its USE site"* — existed in **three
hardcoded copies**: `PyImportRootIsConsumedOnly` for `from X import a`, plus two
inline `CaseEqual` chains in the plain `import X` path. The copies had drifted:

| | plain `import X` | `from X import n` |
| --- | --- | --- |
| sys, os, textwrap, select | ok | **FAIL** |
| dataclasses, `__future__` | **FAIL** | ok |
| typing, itertools | ok | ok |

Six roots, not the two reported — and **the reverse direction was unreported
entirely**. The ticket's hypothesis ("the from-path is not consulting whatever
table the plain path uses") was right in spirit and wrong in shape: both paths
have a table, and neither is authoritative.

Checked on disk rather than assumed: **none** of sys, os, textwrap, select,
typing, itertools, dataclasses, `__future__` has a unit or a `mimic_` shim
anywhere. `random`, `collections` and `math` DO (`lib/rtl/*.pas`) — which is why
they resolve either way and why this went unnoticed.

### Fix

`PyImportRootHasNoBackingUnit` is the single source of truth. Each spelling names
the one root it *genuinely* treats differently, at the site where the reason is
visible: `collections` is consumed by the from-spelling but must NOT be by the
plain one (or `collections.Sym` has no unit to resolve against); `random` is the
mirror case. The next root now has to be added once.

22 cells (11 roots x 2 spellings) green at HEAD; 6 fail on pinned v349.
`test/test_nilpy_import_spellings.npy` imports every root **both ways in one
file**, so adding a root to one path and forgetting the other fails in
test-nilpy instead of in a corpus scan months later. Wired by name into
`test-nilpy` **and** `test-core` (neither globs). gate.sh quick GREEN.

## Explicitly NOT a ladder move

`html5lib/_tokenizer.py` does `from sys import version_info` (line 6) and USES
it at line 21. It now advances from an import wall to an undefined-variable wall
on the same name. **Moved ONTO the next wall, not past it** — the compile count
does not change. Reporting it as ladder movement would be wrong.

## On the title's premise — measured, and the correction needs correcting

The coordinator flagged mid-session that "import sys works" is false because
`sys.version_info` throws at runtime, and suggested the honest shape might be
"sys is unimplemented, fails three ways" (possibly Track B, write a shim).
**Measured, and that generalises too far:**

| | |
| --- | --- |
| `import sys; sys.argv` | **works** (returns 1) |
| `import os; os.getcwd()` | **works** |
| `import sys; sys.version_info` | throws — that MEMBER is missing |
| `from sys import argv; argv` | import resolves now; `argv` undefined |

So `sys` is implemented and its members work; **one member is missing**. The
premise "import sys works" is true for real members, and the failing case was
generalised from a single absent one. No shim is wanted — `sys` is
compiler-provided, and adding `mimic_sys` would create a second competing `sys`,
exactly as this ticket warned in its own "do NOT close this by writing a
mimic_sys" section. Stays Track N; lane unchanged.

## Two separate defects this exposed — filed, not folded in

- [[bug-n-a-from-import-of-a-compiler-provided-module-binds-no-names]] — the
  real next wall, and general.
- [[bug-n-a-guard-reports-its-own-failure-and-lets-the-call-through]] — the
  runtime message states in plain words that its guard did not guard.

Neither belongs here: this ticket was the resolver divergence and that is closed.

## Log
- 2026-08-18 — resolved, commit PENDING-COMMIT.
