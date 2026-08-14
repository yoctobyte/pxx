---
track: N
prio: 55
type: bug
summary: "The lexer rename of `Exception` -> `PyException` leaks into observable Python: `type(e).__name__` gives 'PyException' and `repr(e)` gives \"PyException('plain')\" where CPython gives 'Exception'. Reproduces in a plain .npy that imports nothing — NOT the synthetic sysutils-collision case. Also `Exception.__name__` is not supported at all."
---

# `PyException` leaks through `__name__` and `repr()`

- **Type:** bug (CPython divergence) — **Track N**.
  Found by Track T on 2026-08-14 while walking the Track U queue with the user,
  who predicted it from the RTTI angle before it was measured.

## Reproduce — no imports, nothing synthetic

```python
try:
    raise Exception("plain")
except Exception as e:
    print("class name:", type(e).__name__)
    print("repr:", repr(e))
    print("str:", str(e))
```

| | pxx | CPython |
| --- | --- | --- |
| `type(e).__name__` | **`PyException`** | `Exception` |
| `repr(e)` | **`PyException('plain')`** | `Exception('plain')` |
| `str(e)` | `plain` | `plain` |

**This is the important part: it is not the sysutils-collision case.** That one
is synthetic and was closed as such
([[decide-merge-variant-c-with-bare-name-collision]]). This reproduces in an
ordinary Python program that imports nothing at all, so it is squarely inside
NilPy's upward-compatibility rule — *code that works on CPython must work on
NilPy*. A program that branches on `type(e).__name__ == 'Exception'`, or that
prints a repr into a log or a test expectation, sees the mangling.

Note the derived classes are FINE — `raise ValueError("boom")` reports
`ValueError` and `ValueError('boom')` correctly. It is only the base class,
i.e. exactly the one the lexer rewrites.

## Second, smaller gap found alongside

```
$ ... print("base name:", Exception.__name__)
pascal26:6: error: class method not found: __name__
  near:  base name:  PyException  __name__ >>>
```

`Exception.__name__` on the CLASS (rather than on `type(e)`) is not supported.
Also worth noting the diagnostic itself prints the mangled name, which is how
the leak was first spotted — the error text is echoing rewritten source back at
the user.

## Shape of the fix

The lexer rewrite is the right mechanism (it is what makes `Exception` a
language builtin rather than a colliding library class), but a rename needs a
**display name mapped back**: whatever surfaces `__name__` / `repr()` should
report `Exception` for the class the rewrite produced. One mapping, at the point
where the class name becomes user-visible, rather than unwinding the rename.

Grep for the other surfaces before closing: `__name__`, `repr()`, `str()` of a
class, traceback rendering, and anything that formats an uncaught exception —
the fix is only complete if all of them agree, and this was found through two of
them by accident.

## Gate

The program above matches CPython line for line, `raise ValueError` still
reports `ValueError`, and an UNCAUGHT base `Exception` prints CPython's name in
whatever traceback pxx emits.
