---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`def f(c=UserWarning)` segfaults at runtime the moment the default is actually taken — no diagnostic, exit 139. Any TYPE as a default value does it (user class, builtin type, builtin exception), whether or not the parameter is then called; ordinary values are fine. Passing the argument explicitly works, so the fault is in materialising the default."
---

# A type as a default parameter value segfaults when the default is taken

- **Type:** bug (silent runtime crash, no diagnostic) — **Track N** (NilPy
  lowering). May turn out to be core; it is filed here because the construct is
  a NilPy default argument. **Not fixed under B.**
- **Found:** 2026-08-17 by frank3, writing `mimic_warnings`, whose CPython
  signature is `warn(message, category=UserWarning, ...)`.
- **Measured against:** `pinned` **v346**. Not re-checked at HEAD.

## Repro

```python
def f(c=UserWarning):
    return c("m")

print(str(f()))          # <-- no argument: the default is taken
```

```
pxx:     Segmentation fault (core dumped), exit 139, no output, no diagnostic
CPython: m
```

## The boundary, one variable at a time

| case | result |
| --- | --- |
| `def f(c): ...` called as `f(UserWarning)` | **ok** |
| `def f(c=UserWarning): ...` called as `f(UserWarning)` — default present but unused | **ok** |
| `def f(c=UserWarning): ...` called as `f()` — default taken | **SEGFAULT** |
| `def f(c=A)` for a user class `A`, called as `f()` | **SEGFAULT** |
| `def f(c=str)` for a builtin type, called as `f()` | **SEGFAULT** |
| `def f(c=UserWarning): return c.__name__` — never *called*, only read | **SEGFAULT** |
| `def f(c=5): return c + 1` | ok |

So it is not about the class being *called*, and not about which class it is:
**materialising a TYPE as a default argument value is what crashes.** Reading
`.__name__` off it is enough. Ordinary values as defaults are unaffected, and
passing the same type explicitly is fine — `bug-n-a-type-name-is-not-a-first-class-value`
made types first-class in value positions, and the default-argument slot looks
like the one position that did not come with it.

## Why it matters more than the construct suggests

1. **It is silent.** No compile error, no runtime message, no partial output —
   exit 139. Every other type-as-a-value gap in this dialect has produced a
   clear diagnostic (`the class W cannot be used as a VALUE yet`,
   `issubclass() takes class NAMES`). This one produces a core dump, which is
   the failure mode this repo's debugging playbook calls the expensive kind.
2. **It breaks NilPy's upward-compatibility contract**: `warnings.warn("x")`
   is ordinary working CPython, and it must work here.
3. `category=SomeWarning` / `cls=SomeClass` is a *very* common Python signature
   idiom — factory functions, `warn`, `raise_for`, serialiser hooks.

## Current workaround, registered

`lib/rtl/mimic_warnings.py` writes `category=None` and substitutes
`UserWarning` inside the body. Registered in
`devdocs/dev/track-b-workarounds.md` with a revert-to note, per the Track B
convention for library code that sidesteps an open compiler bug rather than
hiding it. Revert to `category=UserWarning` when this lands.

## Gate

The repro above prints `m` and exits 0, and all six SEGFAULT rows in the table
become ok. Then `mimic_warnings`'s signature reverts and its registry entry is
dropped.
