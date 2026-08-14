---
track: N
prio: 35
type: bug
blocked-by: []
summary: "`MyErr('no such user', 404).args` is `(\"('no such user', 404)\",)` — one string — where CPython gives `('no such user', 404)`, two elements. The multi-argument fold renders the arguments at the construction site, so args gets the TEXT. str(e) agrees with CPython; only args and len(args) differ."
---

# A multi-argument raise loses its argument tuple to the fold

Measured 2026-08-14 at HEAD, after
[[bug-nilpy-non-keyerror-exception-args-loses-the-argument-type]] fixed the
single-argument case:

```python
class MyErr(Exception): pass
try:
    raise MyErr("no such user", 404)
except MyErr as e:
    print(e.args, len(e.args), str(e))
```

| | pxx | CPython |
| --- | --- | --- |
| `e.args` | `("('no such user', 404)",)` | `('no such user', 404)` |
| `len(e.args)` | `1` | `2` |
| `str(e)` | `('no such user', 404)` | agrees |

So `code = e.args[1]` next to `raise MyErr("no such user", 404)` — the exact
idiom `args` exists for — reads the wrong thing, and `len(e.args)` is 1 for
every multi-argument exception in the language.

## Cause

`Exception` takes ONE parameter, so the multi-argument arm in `pyparser.inc`
folds the arguments into the single message CPython would print —
`'(' + repr(a) + ', ' + ... + ')'` — at the construction site. `args` is then
derived from (or stored as) that one rendered string.

The single-argument case was fixed by widening the base ctor to a Variant, and
that does not extend here: the problem is not the argument's TYPE, it is that
there is one parameter and N arguments.

## Shape of a fix

The fold already visits every argument and boxes each through `pyvar_repr`. It
needs to ALSO build a `TPyList` marked `PYSEQ_TUPLE` from the same arguments and
stash it in the `argsv` slot the base class already has (KeyError uses it; the
storage and `GetArgs`' preference for it are both in place).

The obstacle recorded when `args` first shipped: **the fold consumes its
argument nodes into the rendered string, so building the tuple as well needs
clones of those nodes** — the same argument evaluated twice would be wrong for
anything with a side effect, so it wants a hoisted temp per argument, evaluated
once, feeding both the repr and the tuple. That is the real work here.

## Gate

The table above matching CPython, `e.args[1] == 404`, the single-argument and
KeyError rows of `test_nilpy_exception_args` and
`test_nilpy_exception_non_string_argument` unchanged, and a multi-argument raise
whose arguments have side effects evaluated exactly once.
