---
track: N
prio: 55
type: feature
---

# NilPy: `Exception(msg)` — the root class takes no arguments

Left out of [[feature-nilpy-exceptions]] (landed cc833c2d) because uforth's
shape — `class ForthThrow(Exception)` with its own `__init__` and `self.code` —
works without it. `try` / `except` / `finally` / `raise` are all in.

## Repro

```python
try:
    raise Exception("neg")
except Exception:
    print("caught")
```

```
pascal26:2: error: undefined variable (Exception)
```

`Exception` is a lazily registered EMPTY shell (`PyEnsureExceptionClass` in
pyparser.inc): it exists as a class for inheritance and for handler matching,
but has no constructor, so it is not callable, and there is no name binding for
it in expression position.

## Shape

- Make `Exception` constructible with an optional message argument, stored in a
  field.
- `str(e)` / `print(e)` should yield that message, which is how Python code
  reads it back. That is the part with real surface area — it means the boxed
  exception has to answer the str path.
- `e.args` is probably not worth paying for; check the corpus first.

Measure before building: census how many corpus sites actually construct a bare
`Exception` with a message versus a typed subclass carrying its own fields.

## Gate

`test-nilpy` green with a `.npy` case diffed against CPython + `--tier quick` +
self-host byte-identical.

## Census (2026-07-21) — it IS needed, broadly

uforth.py has **85 raises of built-in exception classes with a message**
(Exception/ValueError/RuntimeError/KeyError/TypeError/IndexError(msg)) in its
NilPy-compiled body, not just typed ForthThrow subclasses. So the initial
"works without it" is wrong for the full port: the built-in exception classes
must be constructible with a message and answer str()/print(). pylib ALREADY
provides the runtime (Exception has `msg` + `Create(m)`; ValueError etc. are
subclasses that inherit it) — the gap is frontend wiring: PyEnsureExceptionClass
registers an EMPTY UClass, and the built-in names are not callable in expression
position. Prio bumped 45 -> 55.
