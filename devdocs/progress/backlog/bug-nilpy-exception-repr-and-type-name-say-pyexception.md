---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`repr(Exception('x'))` prints `PyException('x')` and `type(e).__name__` is `PyException`, where CPython says `Exception`. Introduced 2026-08-14 by the option-5 rename: ClassName reports the DECLARED class name and the declared name is now PyException. Ordinary Python branches on type(e).__name__, so this is an upward-compatibility break, not a cosmetic one."
---

# `repr()` and `type(e).__name__` leak the internal `PyException` name

Measured at HEAD:

| | pxx | CPython |
| --- | --- | --- |
| `repr(Exception('x'))` | `PyException('x')` | `Exception('x')` |
| `type(e).__name__` | `PyException` | `Exception` |
| `repr(ValueError('v'))` | `ValueError('v')` | agrees |

Only the ROOT is affected — every named subclass declares its own Python
spelling, so `ValueError`, `KeyError` and the rest are correct. That is exactly
why the existing tests missed it: `test_nilpy_exception_args` asserts
`ValueError('v')` and `KeyError('inner')`, and nothing asserted a bare
`Exception`.

## Cause, and it is self-inflicted

[[decide-pylib-exception-vs-sysutils-exception]] option 5 renamed pylib's root
class to `PyException` so it would stop colliding with sysutils'. `ClassName`
(and therefore `repr` and `type(e).__name__`) reports the **declared** name of
the class, and the declared name is now the internal one. The lexer maps the
bare identifier on the way IN; nothing maps it back on the way OUT.

## Why it matters

`if type(e).__name__ == "Exception":` and error text that embeds `repr(e)` are
ordinary Python. Under NilPy's rule — *if code works on CPython, it must work on
NilPy* — this is a real break, not a divergence to document.

## Fix

**Fixed by construction** by [[feature-a-one-exception-class-in-a-shared-unit]]:
the shared class is NAMED `Exception` and pylib reaches it through an alias, so
`ClassName` is `Exception` again. Verified in the prototype for that ticket
(`bare root ClassName: Exception`).

If that lands, close this with it. The standalone alternative — special-casing
the name in the renderer and in `__name__` — is a second place that has to know
the mapping, and mapping-in-one-direction-only is what caused this.

## Gate

`repr(Exception('x'))`, `str(Exception('x'))`, `type(e).__name__`, and a
subclass's `__name__`, all diffed against CPython. Add the bare-root rows to
`test_nilpy_exception_args.npy` — their absence is why this shipped.
