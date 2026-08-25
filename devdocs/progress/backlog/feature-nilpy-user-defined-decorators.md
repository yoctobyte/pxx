---
prio: 68
track: N
type: feature
blocked-by: []
summary: "A user-defined decorator — the ordinary `@wrap` over a `def`, not one of the four recognised names — is refused at parse time: \"unsupported decorator (only @dataclass and @overload)\". The decorator list is a NAME whitelist, so nothing a program declares itself can appear in it."
---

# A decorator that is not one of the recognised names is refused

```python
def deco(f):
    def w():
        return "wrapped:" + f()
    return w

@deco
def g():
    return "g"

print(g())          # CPython: wrapped:g
```

```
pascal26:9: error: Nil Python: unsupported decorator (only @dataclass and @overload)
  near:   w    >>> deco
```

Found 2026-08-15 while gating [[bug-nilpy-matmul-operator-does-not-parse]] —
the first draft of that test used an ordinary decorator as its "decorator `@`
still parses" control and could not compile. `@property`,
`@staticmethod`/`@classmethod`, `@dataclass` and `@overload` all work; the
message names only two because the other two are recognised elsewhere.

## Why it is a whitelist

Every decorator site in `pyparser.inc` matches on the NAME after the `@`
(`'property'`, `'dataclass'`, …) and rewrites the def accordingly. There is no
general path, so a decorator that is an ordinary callable has nowhere to go.

## What the general form needs

`@d` over `def g(...)` is exactly `g = d(g)` after the def — that is the whole
semantics, including stacking (bottom-up) and `@d(arg)` where the decorator
expression is itself a call. So the shape is a desugaring, not new machinery:
declare the function, then rebind the name to the call result. The two catches:

- **The name's TYPE changes.** After decoration `g` holds whatever `d` returned
  — in the example a closure, not the original function — so the binding has to
  become a callable VALUE, which is the ground
  [[project_nilpy_callable_has_three_representations]] warns about: crossing the
  three callable representations writes a variant tag into a pointer slot.
  Whether the rebind can use the existing closure representation is the first
  thing to measure, not to assume.
- **The recognised four must keep their current lowering.** `@dataclass` and
  `@property` are not `f = dataclass(f)` here — they rewrite the declaration.
  So the general path is a FALLBACK for unrecognised names, and the whitelist
  stays as the fast path rather than being replaced.

## Prio

30. Loud, not silent, and the decorator idiom is common enough in ordinary
Python (`@functools.wraps`, test registries, memoisation) that a real corpus
will hit it — but no corpus in this repo is waiting on it today, and the
callable-representation question above means it is not a small change.

## Gate

`.npy` diffed against CPython: a plain decorator, a stacked pair (applied
bottom-up), a decorator taking arguments, a decorated METHOD, and the four
recognised names still lowering exactly as they do now.
