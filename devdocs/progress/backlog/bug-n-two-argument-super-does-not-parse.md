---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`super(Cls, self).__init__(x)` is `error: unexpected token`, while the zero-argument `super().__init__()` works. The two-argument form is Python 2's spelling, still valid Python 3 and still what portable libraries write — html5lib uses it in every filter. It is now the wall html5lib/filters/sanitizer.py sits on, the file the six.moves work was aimed at."
---

# Two-argument `super(Cls, self)` does not parse

- **Type:** bug — **Track N** (Nil-Python frontend, parser).
- **Found:** 2026-08-18 by frank3-fc, re-running the ladder after landing
  [[feature-b-mimic-six-moves-needs-http-client-and-urllib]]'s `urllib_parse`
  half — this is what `sanitizer.py` moved onto.
- **Measured against:** `pinned` **v351** (`e4ca45a1819c`, pin `a6d6dfb84`).
- CPython accepts and runs both forms.

## Repro

```python
class A:
    def __init__(self):
        self.v = 1

class B(A):
    def __init__(self):
        super(B, self).__init__()      # error: unexpected token

print(B().v)
```

Replace the call with `super().__init__()` and it compiles and prints `1`.

| form | result |
| --- | --- |
| `super().__init__()` — zero-argument | ✅ |
| **`super(B, self).__init__()` — two-argument** | **error: unexpected token** |

## Why it is worth filing rather than shrugging at

The two-argument form is not legacy trivia: it is what every library written to
run on both Pythons still contains, and it remains valid Python 3. html5lib
writes it in **every** filter — `super(Filter, self).__init__(source)` — so it
is not one file's habit.

Concretely it is now the wall on `html5lib/filters/sanitizer.py:769`, which is
the file the `six.moves` `urllib_parse` work existed to unblock. That work
landed and moved the file exactly one step, onto this.

The diagnostic is also unhelpful — "unexpected token" with no mention of
`super` — so a reader meets it as a mystery rather than as a missing feature.

## Note for whoever takes it

Related but not the same, and worth checking together since they are one
concept with two spellings
(`devdocs/dev/normalise-dont-special-case.md`): the zero-argument form already
works, so the machinery exists and this is about accepting the explicit
arguments and checking they name the enclosing class and `self`. Do not grow a
second path for it.
