---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`super(Cls, self).__init__(x)` is `error: unexpected token`, while the zero-argument `super().__init__()` works. The two-argument form is Python 2's spelling, still valid Python 3 and still what portable libraries write — html5lib uses it in every filter. It is now the wall html5lib/filters/sanitizer.py sits on, the file the six.moves work was aimed at."
status: done
owner: frank2-7e
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

## RESOLVED 2026-08-18 (frank2-7e, Track A+N) — one consumer for both spellings

Reproduced at HEAD (v352 ground, not the pinned v351 the ticket measured) and
fixed as the ticket's own note asked: no second path.

### There are TWO parse sites, and one of them is in a SHARED file

Worth stating because it is what makes this an A/P-slot job rather than a pure
Track N one:

- statement position — `compiler/pyparser.inc` (`super(B, self).__init__()`)
- **expression position — `compiler/parser.inc`** (`return "B" + super(B, self).who()`)

Both did `Expect(tkLParen); Expect(tkRParen)`, i.e. the zero-argument spelling
was hard-coded twice. Fixing only the statement site would have left the
expression form failing, and fixing them separately would have been the second
path the ticket warned about.

### The fix

`PySuperConsumeArgs` (new, `pyparser.inc`, forward-declared in `parser.inc`
beside `PyMakeSuperCall`): consumes `super`'s argument list in EITHER spelling.
Both sites now call it, and `PyMakeSuperCall` — the lowering — is untouched.
`super(Cls, self)` means "start the lookup after Cls", which for the enclosing
class is exactly what `super()` already means, so the two spellings genuinely
are one concept and now share one implementation.

### What is REFUSED, loudly, rather than guessed

`super(A, self)` inside `class B` asks to start the lookup ABOVE the enclosing
class. That is a different lowering from the inherited call this builds, so it
is refused by name instead of being silently treated as `super(B, self)`:

```
error: Nil Python: super(A, self) inside class B — starting the lookup above the
enclosing class is not supported; super(B, self) and super() are
```

Same for the shapes around it, each naming `super` and saying what to write —
the ticket's second complaint was that the old diagnostic never mentioned it:

| written | diagnostic |
| --- | --- |
| `super(B, cls)` | only `self` is supported as the second argument (a classmethod super is not) |
| `super(B)` | the one-argument form is an unbound super and is not supported |
| `super(type(self), self)` | the first argument must be a plain class name, not a computed expression |
| `super(1, 2)` | takes either no arguments or `super(<class>, self)` |

### Corpus effect — ONTO the next wall, not past it

Reported past-vs-onto, per the campaign's rule. **Zero files compile
completely.** What moved, HEAD vs pinned v351:

| file | pinned v351 | HEAD |
| --- | --- | --- |
| `html5lib/filters/sanitizer.py` | `:769 unexpected token` | `:788 undefined variable (yield)` |
| `html5lib/filters/lint.py` | `:26 unexpected token` | `:93 undefined variable (yield)` |

Both cleared the super wall and landed on `yield` —
[[feature-nilpy-yield-outside-a-for-loop]], which is parked with its diagnosis
banked. The compounding this ticket and the shim work were ranked for is real,
and `yield` is now the wall in front of the filter pipeline.

### Verified

The ticket's repro; the zero-argument form (unchanged); two-argument with
arguments; the two-argument form in EXPRESSION position (the second parse site);
and the exact html5lib `super(WhitespaceFilter, self).__init__(source)` shape —
all match CPython.

**Test:** `test/test_nilpy_two_argument_super.npy`, wired into BOTH `test-nilpy`
and `test-core`.

**Gate:** `make compiler/pascal26` fixedpoint (converged after 1 round) +
`tools/gate.sh quick` GREEN. Shared file `parser.inc` touched — A/P slot was
declared to the coordinator and held for the whole job.

## Log
- 2026-08-18 — resolved, commit 60d5a6c43.
