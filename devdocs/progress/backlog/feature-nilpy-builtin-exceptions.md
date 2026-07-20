---
track: N
prio: 55
type: feature
---

# NilPy: Python's builtin exception classes, and `int(s, base)` that raises

Hangs off [[feature-nilpy-corpus-uforth]]. This is uforth's wall as of
2026-07-20, at uforth.py:359, after os.path/one-line-suites landed.

## The wall, and why it is bigger than it looks

```python
try:
    val = int(s, base)      # two-argument int() with a radix — not supported
    ...
except ValueError:          # ValueError is not a declared class — not supported
    pass
```

Two separate gaps, and they must land together to be useful:

1. **`int(s, base)`** — the two-argument radix form. `parser.inc`'s NilPy
   `int(` handler (search `isNilPy and (name = 'int')`) parses exactly one
   argument and then expects `)`. The one-argument forms already lower to the
   -203 (Trunc) and -200 (parse/unbox) intrinsics.
2. **Builtin exception classes.** `except ValueError:` resolves the class name
   through `FindUClass`, so only `Exception` (via `PyEnsureExceptionClass`) and
   user-declared classes work. Python's builtins are not declared anywhere.

**Do not implement `int(s, base)` with the usual pylib error path.** Every
other pylib failure does `WriteLn(...); Halt(1)`. That is fatal here: a Forth
interpreter tries EVERY input word as a number first, so a non-numeric token is
the common case, not an error case. `pyint_parse` must raise something
`except ValueError` can catch, or uforth dies on its first ordinary word.

## Census — the exception classes uforth catches

`AttributeError`, `EOFError`, `Exception`, `ForthThrow` (its own, already
works), `KeyboardInterrupt`, `OSError`, `ValueError`.

## Shape

- Predeclare the builtin hierarchy the way `PyEnsureExceptionClass` already
  creates `Exception` — lazily, on first reference, so a program that never
  names them pays nothing. All descend from `Exception` so a bare
  `except Exception:` still catches them.
- The open question is how **pylib** raises one: the classes are created by the
  FRONTEND at parse time, so a Pascal unit cannot name them directly. Options:
  (a) have the frontend lower `int(s, base)` to a pylib call returning a
  success flag and synthesise the `raise` in the AST at the call site;
  (b) give pylib a raise-by-class-name runtime helper.
  (a) keeps pylib free of frontend knowledge and is the recommended route.

## Gate

`make test-nilpy` green with a `.npy` case diffed against CPython (must cover
a FAILING parse caught by `except ValueError`, not just a succeeding one, since
the catch is the whole point) + `--tier quick` + self-host byte-identical +
`make fpc-check` clean relative to HEAD.
