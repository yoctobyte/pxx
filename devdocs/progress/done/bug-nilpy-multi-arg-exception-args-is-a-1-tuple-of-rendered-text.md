---
track: N
prio: 35
type: bug
blocked-by: []
summary: "`MyErr('no such user', 404).args` is `(\"('no such user', 404)\",)` — one string — where CPython gives `('no such user', 404)`, two elements. The multi-argument fold renders the arguments at the construction site, so args gets the TEXT. str(e) agrees with CPython; only args and len(args) differ."
status: done
owner: agent-AN
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

## Resolution (2026-08-15)

Fixed by **inverting the order**: build the tuple at the construction site, then
derive the message FROM the tuple at run time. That dissolves the obstacle the
"Shape of a fix" section records — no clones and no per-argument temps are
needed, because each argument is now parsed and lowered exactly once, into the
tuple, and the rendered text is a pure function of the finished tuple.

- `compiler/builtin/pylib.pas`: `pyexc_tuplemsg(t)` returns `pylist_repr(t)` —
  the same `('no such user', 404)` text the fold used to concatenate by hand —
  and `pyexc_setargs(e, t)` stores the tuple into the `argsv` slot the base
  class already had.
- `compiler/pyparser.inc`: new `PyMakeTupleFromArgs(firstArg)` builds a
  `PYSEQ_TUPLE` `TPyList` from an already-parsed AN_ARG chain via a hoisted
  temp (`pylist_mark_tuple` + `append_self`). The multi-argument fold now calls
  it, passes `pyexc_tuplemsg(tup)` as the ctor's one argument, and wraps the
  finished node in `pyexc_setargs`, keeping `ASTRight` so the record identity
  survives.

`PyMakeTupleFromArgs` is used ~6800 lines above its definition; pxx accepts
that, FPC does not, and the seed canary caught it. Forward declaration added
beside `PyUserNameShadowsHere`'s — third instance of this shape this session,
after `bug-a-fpc-seed-drift-emitasmx64-forward`.

Verified byte-identical to CPython, including the side-effect row that motivated
the ticket:

```
args    ('no such user', 404) 2
index   no such user 404
istuple True
args3   ('a', 1, 2.5) 3
sides   ('x', 7) ['x', 7]      <- each argument evaluated exactly once
args1   ('solo',) 1
args0   () 0
argsbi  ('v', 2) 2
argskey ('nope',) 1 'nope'
```

`test/test_nilpy_exception_multi_arg.npy` extended in place (+`.expected`
refreshed). All twelve pre-existing `test_nilpy_(exception|raise|except)*` tests
re-diffed against CPython and unchanged.

Gate: `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN
(self-host, testmgr quick, FPC seed canary).

## Log
- 2026-08-15 — resolved, commit d135e88d1.
