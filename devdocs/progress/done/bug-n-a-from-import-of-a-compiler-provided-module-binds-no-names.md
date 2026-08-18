---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`from sys import argv` now resolves but binds nothing — a bare `argv` is `undefined variable` while `sys.argv` works. Consuming a from-import of a compiler-provided root (sys, os, textwrap, select, typing, itertools, dataclasses, __future__) discards the names it publishes, so the spelling CPython programs actually use is the one that does not work. General across all eight roots."
status: done
owner: frank2-7e
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

## RESOLVED 2026-08-18 (frank2-7e, Track N) — remember the root, reuse the intercepts

Landed as the ticket's "shape of the fix" describes: the binding, not a shim,
and no second table of members.

### What was measured first

The failure is general across BOTH import arms, which the ticket did not know:

| written | before |
| --- | --- |
| `from sys import argv` -> `argv` | undefined variable |
| `from sys import exit` -> `exit(0)` | undefined variable |
| `from os import getenv` -> `getenv(k)` | undefined variable |
| `from os.path import join` -> `join(a, b)` | undefined variable |
| `from textwrap import dedent` -> `dedent(s)` | undefined variable |
| `from random import randint` -> `randint(a, b)` | undefined variable |
| `from math import sqrt` -> `sqrt(x)` | ✅ already worked |

`math` works because it has a backing unit whose names become visible. Every
failing row is a name the compiler provides through an INTERCEPT — the value
intercept (`PyIsSysStreamAhead`) or the call table (`PyStdlibCallProc`) — and
the from-spelling reached neither.

### The fix

A small per-module registry (`PyStdAlias*`): a from-imported name, the MEMBER it
names, and the dotted root it came from, tagged with the importing unit exactly
as `PyImpName` is. Then the two existing intercepts learn the bare spelling:

- `PyIsStdlibMemberValue(base, nm, anyAttr)` — split out of the token predicate
  so the dotted and bare spellings ask ONE membership question
- `PyStdlibCallAhead` — a bare aliased name before `(` composes `root.member`
  and consults the SAME `PyStdlibCallProc` table, occupying one token instead
  of three

So an entry can never exist for one spelling and not the other, which is the
property the ticket's note was after.

### Three things measurement corrected mid-fix

1. **`as` renames need the MEMBER, not the local name.** `from sys import argv
   as av` binds `av` and still means `sys.argv`; storing only the local spelling
   resolved nothing.
2. **Which import ARM a root takes says nothing about whether its members are
   compiler-provided.** `random` has a backing unit, so it never reaches the
   consumed-only arm — but `random.randint` lives in the same call table
   `sys.exit` does. The recorder is called from BOTH arms.
3. **`PyDottedImport` is a global and `ParseUsesUnit` overwrites it.** Pulling a
   unit parses ITS imports, so the unit arm read the wrong root and bound
   nothing. Captured into a local before the pull.

### What deliberately did NOT change

`from sys import nosuch` still walls at COMPILE time as an undefined variable.
The qualified `sys.nosuch` answers any attribute with a runtime AttributeError
(the `sys._MEIPASS` shape), and letting the bare form take that arm would have
turned a compile error into a weaker runtime raise for a name nothing provides
— the opposite of what the consumed-only policy is after. The `anyAttr` flag is
exactly that distinction.

### Verified

Every row above, plus: `as` renames (value and call), multiple names in one
import, a rename beside a plain name, the qualified spellings unchanged,
`file=stderr` from a from-import, a later `def` rebinding the name (matches
CPython's ordering — the call above the def still reaches the import), an
assignment rebinding it, and **per-module scoping** — `from os.path import join`
inside a module does NOT bind `join` in the importing program.

### Corpus: no movement, and that is the honest report

Zero ladder files moved. The from-spelling of these roots barely appears in
html5lib/tinycss2/webencodings; this was found while closing
[[bug-n-from-sys-import-fails-while-import-sys-works]] and it fixes the spelling
real CPython programs use, not a corpus wall.

**Test:** `test/test_nilpy_from_import_binds_provided_names.npy`, wired into BOTH
`test-nilpy` and `test-core`.

**Gate:** `make compiler/pascal26` fixedpoint (converged after 1 round) +
`tools/gate.sh quick` GREEN. `pyparser.inc` only — no shared file, no A/P slot.

## Log
- 2026-08-18 — resolved, commit PENDING-COMMIT.
