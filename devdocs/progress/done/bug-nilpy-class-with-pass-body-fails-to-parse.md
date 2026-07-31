---
track: N
prio: 50
type: bug
---

# NilPy: a class body of only `pass` fails to parse

Found while testing `feature-nilpy-aggregate-builtins`'s `type(x).__name__`
addition (an empty exception subclass was the natural first thing to try it
on).

```python
class MyErr(Exception):
    pass
```

```
Expected: def, but got: pass (Kind: 1, Line: 2)
pascal26:2: error: unexpected token
```

Not specific to inheriting `Exception` — a plain `class Empty: pass` hits the
same error.

## Cause

`PyParseClass`'s body loop (pyparser.inc) has a case for a docstring, a
class-attribute line, a `@decorator`, and a nested `class`; every other
leading token falls into an unconditional `PyParseMethod(ci)` call, which
immediately does `Expect(tkFunction, 'def')`. A bare `pass` — the idiomatic
empty body — has no case of its own, unlike every OTHER `pass` site in the
grammar (the statement-level one already skips it).

## Fix

Gave the class-body loop the same `pass`-skip the statement level already has.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` covering an empty
`class X(Exception): pass` (raised, caught, `type(e).__name__` read back) and
a plain `class Empty: pass` (constructed), diffed against CPython.

## Resolved

Fixed and gated green — commit f3db58864a3c20b0015c16e0cabe6fdecc0380c9.
Regression: `test/test_nilpy_class_pass_body.npy`.

## Log
- 2026-07-31 — resolved, commit f3db58864a3c20b0015c16e0cabe6fdecc0380c9.
