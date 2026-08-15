---
track: N
prio: 35
type: bug
blocked-by: []
commit: PENDING-COMMIT
summary: "`lambda a, b=2:` was a parse error — the frontend read every `name=value` in a lambda header as the `key=key` CAPTURE idiom and demanded a bare name. There is no such thing as a capture in Python: it is a default argument evaluated at definition time, which is now the one path all of them take."
---

# `lambda a, b=2:` does not parse

```python
f = lambda a, b=2: a * b
print(f(3), f(3, 4))     # CPython: 6 12
```

```
pascal26:1: error: Nil Python: a lambda default capture must be a plain name (key=key)
```

Found 2026-08-15 by a CPython differential sweep (`tools/pydiff.py`), which
walled on the line above before it could check anything after it.

## Cause — a Python idiom mistaken for a Python feature

`PyParseLambdaStub` treated `name=<value>` in a lambda header as a **capture**:
"Python's idiom for capturing a loop variable by value, not a parameter the
caller ever supplies", and therefore accepted only a bare name as the value.

That reading is backwards. CPython has no capture construct at all — `key=key`
is an ordinary DEFAULT ARGUMENT whose value is evaluated at definition time,
which is *why* it pins the loop variable. The caller can always override it, and
the value can be any expression. Reading the idiom as the feature made the
feature (`b=2`) unrepresentable.

## Fix — one path, and it is the definition-time evaluation Python specifies

Every default now parses as an expression and is materialised into a hidden
local right there, before the lambda is built. Definition-time evaluation falls
out of *where* the assignment is hoisted, and the rest of the routine keeps
seeing "a plain name", so the binding, arity and override machinery are
untouched.

The bare-name arm was DELETED rather than kept as a fast path, and that fixed a
second bug on its own: it bound the enclosing symbol directly, so the bind was
chosen off that symbol's static type. Fine for an Int64; for a `str` default,
`s = lambda t, sep=sp: sep.join(t)` raised **"TypeError: expected a number, got
str"** the moment a caller overrode it. Two paths, one of them wrong for
everything but ints — `devdocs/dev/normalise-dont-special-case.md`.

## The measurement that mattered

The first version typed the hidden local by the value's static type, and
`b=1+1` bound **-6384382** while the identical `b=2` was correct. `PXXDBG=n.locals`
printed the temp as **tk=28** — a PROMOTABLE int, two machine words — and the
bind reads ONE word out of the slot. A literal is already Int64, which is why
the constant case looked fine and every arithmetic default was garbage. The temp
is now always a **variant**: it is what the lambda's own parameters are, it
carries every value kind, and it routes through `pyboundfn_bind_var`, the path
written for exactly this.

Worth keeping from the same dump: the typing pre-pass allocates the temp once
per round (four `__py_lamdef_*` locals for one lambda). Harmless — each round's
assignment and bind agree — but it is what a hidden local looks like here.

## Gate

`test/test_nilpy_lambda_default_values.npy` (+`.expected`, in the Makefile),
byte-identical to CPython: literal, arithmetic, name, name-arithmetic, call,
unary-minus, float, subscript, list, dict, bool and None defaults; two and three
defaults at once; a zero-parameter lambda with a default; the override of each;
the `i=i` loop-capture idiom still pinning per iteration; and left-to-right
evaluation of several defaults. Every pre-existing `test/*lambda*` /
`*closure*.npy` re-diffed against CPython. `gate.sh quick` GREEN.
