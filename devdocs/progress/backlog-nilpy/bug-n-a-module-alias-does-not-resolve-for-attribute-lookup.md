---
slug: bug-n-a-module-alias-does-not-resolve-for-attribute-lookup
title: "`import sys as s; s.platform` does not compile — a module alias is not mapped to its base for ATTRIBUTE lookup, only for calls"
track: N
type: bug
prio: 55
status: open
found: 2026-08-29
found-by: claude-N
---

# A module alias resolves for calls but not for attributes

Working CPython code does not compile. One direction, which is the direction
NilPy promises:

```python
import sys as s
print(s.platform)        # pxx: no member platform came of the qualifier s
import os as o
print(o.SEEK_CUR)        # pxx: no member SEEK_CUR came of the qualifier o
print(o.sep)             # same
```

All three run fine on CPython. The unaliased spellings all work:

| spelling | result |
| --- | --- |
| `import sys` + `sys.platform` | ok |
| `from sys import platform` | ok — the bare form is handled |
| `import sys as s` + `s.platform` | **fails to compile** |

So both spellings that exist today are covered and the alias is the one that
is not. `PyStdAliasLookup` already exists and already maps the bare
from-imported name to its base; the qualified-with-an-alias form never asks it.

## Where it is

`PyIsStdlibMemberValue(base, nm, anyAttr)` gates on `base = 'sys'` / `'os'`,
and its callers pass the QUALIFIER TOKEN as written. For `import os as o` that
token is `o`, which matches no arm, so the whole stdlib-member route is skipped
and the ordinary member lookup then reports "no member ... came of the
qualifier o".

The fix is to resolve the qualifier through the import-alias table before the
membership test, in the same place the bare form is already resolved — not to
add a second table.

## Not the same as the CALL path

`import os as o; o.path.basename(p)` — worth measuring separately. The dotted
CALL table (`PyStdlibCallAhead` / `PyParseStdlibCall`) is a different route
from the attribute one, and may or may not have the same hole. **Measure it
before assuming either way**; this ticket was written from measurements of the
attribute path only.

## Provenance

Found while adding `os.sep` / `os.linesep`
([[feature-nilpy-stdlib-coverage-gaps-measured]], landed 2026-08-29). It is
**pre-existing and unrelated to that change** — `s.platform` has never worked
and `platform` predates it — so it was filed rather than folded into that
commit.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` test covering the
aliased spelling of both an attribute (`s.platform`, `o.sep`) and a constant
(`o.SEEK_CUR`), against a CPython-generated `.expected`.

# Re-measured 2026-09-10, frankB, compiler `ca814b0aabcc` — STILL LIVE, verbatim

```python
import sys as s
print(s.platform)
```
```
pascal26:2: error: no member platform came of the qualifier s — check what s
resolves to; an import that bound nothing gives exactly this (s.platform)
```

Filed 2026-08-29, unchanged twelve days later. Recorded because a re-probe that
finds a ticket still true is worth the same line as one that finds it stale —
the next reader otherwise cannot tell an un-re-measured ticket from a
re-measured one.

Adjacent, and probably the same neighbourhood rather than the same cause:
[[bug-n-a-module-bound-by-an-import-is-not-a-value]], filed the same day. Both
are about a NAME THAT STANDS FOR A MODULE — here the alias resolves for a call
and not for an attribute; there the module resolves for an attribute and not as
a value. Neither is a missing feature in the resolver; both are doors that know
about modules in one position and not another.
