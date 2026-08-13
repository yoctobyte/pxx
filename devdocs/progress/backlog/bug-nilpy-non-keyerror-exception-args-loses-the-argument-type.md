---
track: N
prio: 30
type: bug
blocked-by: []
summary: "`ValueError(42).args` is ('42',) where CPython says (42,) — every exception below KeyError still takes a string message, so a non-string argument is rendered at the construction site and its type is gone. str()/repr() are exact; only the args TYPE differs."
---

# Non-KeyError `e.args` keeps the text, not the argument

Residual of [[bug-nilpy-raise-keyerror-with-a-non-string-argument-segfaults]],
which fixed the segfault and left this measured:

| shape | pxx | CPython |
| --- | --- | --- |
| `ValueError(42).args` | `('42',)` | `(42,)` |
| `str(ValueError(42))` | `42` | `42` — agrees |
| `KeyError(42).args` | `(42,)` | `(42,)` — agrees |

So it bites exactly one thing: `e.args[0] == 42` is False for every exception
except KeyError, and `e.args[0] + 1` raises rather than answering 43.

## Cause

`Exception.Create(const m: AnsiString)` in pylib is the base of the whole tree,
and the frontend renders a non-string argument through `pyexc_msgstr` before
the call. KeyError escapes it because it declares its own `Create(const m:
Variant)`.

## Shape of a fix

Widening the base ctor to a Variant is the whole fix and is one line — but
`Exception` here SHADOWS sysutils' for every RTL unit a `.npy` pulls, so every
`raise EConvertError.Create('..')` in the RTL recompiles against the new
signature. That is a Track A-shaped blast radius, not something to land under a
quick-only gate on a Wednesday; it wants its own session and a look at whether
the RTL descendants declare their own ctors.

The narrower alternative is a stored `argsv` on the base (the slot already
exists — KeyError uses it) set by a variant-taking secondary constructor, with
the frontend targeting that ctor by name at the construction site. That needs
the construction path to be able to pick a ctor other than `create`, which it
cannot today (`FindUMeth(ci, 'create')` is hardcoded).

## Gate

`ValueError(42).args[0] + 1` == 43 diffed against CPython, the KeyError rows
unchanged, and the RTL's own raises still catchable (`import json` reaches
sysutils, which is the canary that caught the last shadowing break).
