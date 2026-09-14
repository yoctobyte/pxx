---
slug: bug-n-a-def-in-an-imported-module-does-not-shadow-a-builtin
title: a def in an imported module does not shadow a builtin
summary: >
  FIXED. Root cause: PyUserShadowsProc asked "does the MAIN PROGRAM declare
  this name" (`ProcUnitIdx = -1`), but Python namespaces are per MODULE, so a
  `def format` / `def str` / `def open` in an imported `.py` module never
  counted as a shadow and every call in that module reached pylib's builtin
  instead. lekkerzeilen's `session.save` therefore wrote `str(it)` -- the
  object's repr -- into the session file. Fixed by scoping the predicate to
  the unit being parsed, and by letting a QUALIFIED `mod.format(x)` reach the
  module's own def, since a qualified name has already named its scope.
  `len` and `sorted` go through a different lowering and are NOT fixed; see
  bug-n-a-def-in-an-imported-module-does-not-shadow-len-or-sorted.
track: N
type: bug
prio: 80
owner: frank-user
status: done
---

## How it was found

Chasing lekkerzeilen's empty scene. A verbose open-water run printed

```
session: <__main__.Session object at 0x20eceba8>: not a word this file has
```

which reads as a wrong value inside `session.parse` -- a `Session` object
where a line of text belongs. It was not. `~/.local/state/lekkerzeilen/session.conf`
is **39 bytes and contains exactly that repr**: the WRITER was wrong, and
`parse` was correctly reporting the one line of a file it could not read.

`session.save` ends

```python
    with open(temporary, "w") as handle:
        handle.write(format(it))
```

and `session.py` defines its own module-level `def format(it)` fifty lines
above. Under pxx that call reached pylib's `format(value)`, which is `str`,
which is the repr. The diagnostic was CORRECT ABOUT SOMETHING ELSE -- the
house failure mode -- and it pointed at the reader for most of an hour.

## Reduction

```python
# sess.py
def format(it):
    return "region %s" % it.region

def save(it):
    return format(it)
```

```python
import sess
print(sess.format(s))   # -> '<__main__.Session object at 0x...>'
print(sess.save(s))     # -> '<__main__.Session object at 0x...>'
```

Both rows are `region rijn` under CPython. The same file as the MAIN `.npy`
is correct, which is what localised it to the unit test rather than to
`format` itself.

## The fix

`compiler/symtab.inc` -- new `PyShadowDeclHere(idx)`, used by both
`PyUserShadowsProc` (which decides whether a name-keyed intrinsic stands
down) and `MatchEligBase`'s `userOnly` drop (which decides whether the
builtin's overloads stay in the candidate set). It answers

```pascal
(ProcUnitIdx[idx] = -1) or
  ((ProcUnitIdx[idx] = CurrentUnitIdx) and UnitIsPyModule(ProcUnitIdx[idx]))
```

-- the main `.npy`, or a `.py` module's own defs while THAT module is being
parsed. The second conjunct is what keeps `sess.format` from hijacking a bare
`format(7.5, ".1f")` back in the main program: scoping it to `CurrentUnitIdx`
is the whole point, and a global "any NilPy module declares this name" test
would have been wrong in the other direction.

`compiler/pyparser.inc` -- the `format` intercept in `PyParseFactorCore`
gained `(qUnit < 0)`. `PyUserShadowsProc` structurally cannot answer for
`mod.format(x)`: it is scoped to the unit being parsed and the caller is a
different unit. A qualified name has already said which scope it means, which
is the reasoning the neighbouring `Ord`/`Chr` arm already spells out.

## What it fixes, measured

| name defined in the imported module | pinned v409 | after |
| --- | --- | --- |
| `format` | `abcd` (the builtin) | `USER` |
| `str` | `abcd` | `USER` |
| `open` | `FileNotFoundError: 'abcd'` | `USER` |
| `abs`, `max` | `USER` | `USER` (unchanged) |
| `len` | SIGSEGV | SIGSEGV (**not fixed**) |
| `sorted` | `[]` | `[]` (**not fixed**) |

The last two rows are split out rather than merged: they go through a
different lowering, and a fixture covering all six would let the four green
rows certify the two red ones.

## Gate

`make test-nilpy` rc=0; self-host `converged`; new fixture
`test/test_nilpy_a_def_in_an_imported_module_shadows_a_builtin.npy`
(+ `test/nilpy_modshadow/sess.py`), wired into the Makefile, GREEN at HEAD and
**RED against the pinned compiler** -- the positive control.

## Log
- 2026-09-14 -- found, fixed, fixture wired, landed.
