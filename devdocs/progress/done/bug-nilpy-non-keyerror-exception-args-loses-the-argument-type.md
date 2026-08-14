---
track: N
prio: 30
type: bug
blocked-by: []
summary: "`ValueError(42).args` is ('42',) where CPython says (42,) — every exception below KeyError still takes a string message, so a non-string argument is rendered at the construction site and its type is gone. str()/repr() are exact; only the args TYPE differs."
status: done
owner: agent-N
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

## RESOLVED 2026-08-14 — the one-line fix the ticket named, once the shadowing was gone

"Widening the base ctor to a Variant is the whole fix and is one line — but
`Exception` here SHADOWS sysutils' for every RTL unit a `.npy` pulls, so every
`raise EConvertError.Create('..')` in the RTL recompiles against the new
signature. That is a Track A-shaped blast radius."

**The shadowing is gone.** pylib's root is `PyException`
([[decide-pylib-exception-vs-sysutils-exception]] option 5), so the blast radius
is pylib's own tree and nothing else. `constructor PyException.Create(const m:
Variant)` is the fix, exactly as written above, and the narrower `argsv`
alternative was not needed.

**No frontend change**, and none was expected: the single-argument arm in
`pyparser.inc` already branches on the ctor's declared parameter type and boxes
the argument when it is a Variant — that branch existed for KeyError. Every
exception now takes the path KeyError took.

### One thing the ticket did not anticipate

`KeyError.Create`'s no-argument path handed `''` down to `inherited Create`.
That was harmless while the base only stored a message; now that the base stores
`args`, an empty STRING is a real one-element tuple `('',)` and an empty TAG is
the no-argument form whose args CPython gives as `()`. It has to pass `m`
itself. The existing `empty: '' ()` row caught it immediately — the value of
having recorded CPython's own output.

### Verified against CPython, not against reason

`test_nilpy_exception_non_string_argument` extended and its `.expected`
regenerated from CPython. Every row matches, including
`ValueError(42).args[0] + 1 == 43`, `ValueError(True).args == (True,)`,
`ValueError('')` vs `ValueError()`, and a user subclass inheriting the widened
ctor. Separately diffed: `int('zz')`, `[1][5]`, `1/0` and `{}['k']` — pylib's
OWN internal raises now carry proper args too, all four identical to CPython.

`test_nilpy_exception_args`, `test_nilpy_rtl_exception_surface`,
`test_nilpy_pyexception_bare_vs_qualified` and both
`test_uses_order_pylib_exception_*` unchanged. Self-host converges at generation
1; `gate.sh quick` GREEN.

## Log
- 2026-08-14 — resolved, commit e3d0870c6.

## 2026-08-14, measured after the ctor widening — one of the two residuals is GONE

Re-ran both residuals at HEAD instead of carrying the old text forward:

- `str(KeyError("inner"))` is **`'inner'`**, matching CPython. It was `inner`
  when the residual was written; widening the base ctor to a Variant fixed it as
  a side effect, because the message KeyError stores is now the repr on every
  construction path and `str(e)` reads that field. **Do not go hunting for it.**
- The multi-argument raise is still real and is now its own ticket:
  [[bug-nilpy-multi-arg-exception-args-is-a-1-tuple-of-rendered-text]].
  `MyErr('a', 404).args` is a 1-tuple of the rendered text, so `len(e.args)` is
  1 and `e.args[1]` is wrong. `str(e)` agrees with CPython.

That is the whole remaining gap in this family.
