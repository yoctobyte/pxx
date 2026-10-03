---
slug: bug-n-yield-from-is-not-implemented
track: N
prio: 65
type: bug
blocked-by: []
status: open
created: 2026-08-30
summary: "`yield from` is refused -- `undefined variable (from)`, i.e. the lexer never sees it as one construct. It is Python 3.3, predates every feature NilPy does implement, and generator delegation is ordinary code in working CPython programs, so by NilPy's upward-compatibility charter it is a bug rather than a divergence. Found by the feature probe that produced the sys.version_info ruling."
---

# N: `yield from` is not implemented

## Repro

```python
def inner():
    yield 1

def outer():
    yield from inner()

print(list(outer()))
```

```
pascal26:4: error: undefined variable (from)
```

The diagnostic is the informative part: `from` is being parsed as an expression
after `yield`, so **`yield from` is not recognised as a construct at all** —
this is a missing form in the statement grammar, not a lowering that fails.
Whatever fixes it is in `compiler/pyparser.inc`, at whatever handles `yield`.

## Why this is a bug and not a divergence

CLAUDE.md's NilPy charter: *if code works on CPython, it must work on NilPy* —
one direction only. Generator delegation is ordinary Python, and this is
**Python 3.3**: it predates every single feature NilPy does implement.

That last point is worth stating because it inverts the natural assumption. The
gap is not "NilPy is a bit behind modern Python" — NilPy has f-strings (3.6),
dict `|` (3.9) and `str.removeprefix` (3.9). The implemented subset is not an
interval; it is the imperative-scripting core plus modern conveniences, with
generator delegation and coroutines missing from underneath it.

## How it was found, and what that says about coverage

Not by a failing program — by a probe suite written to answer a *different*
question: what version should `sys.version_info` claim
([[decide-nilpy-what-version-does-sys-version-info-claim]], owner 2026-08-30).
Nine feature probes, and this was one of two that failed far below the level
anyone expected.

**A gap this old surviving in a suite with real coverage** — SQLite CRUD,
classes, variants, string methods — says the suite is broad in library surface
and thin in *language* surface. Worth a look at whether the same is true
elsewhere, independently of this fix.

## Scope note

`yield from` is not sugar for a `for` loop that re-yields: it forwards `send()`,
`throw()` and `close()`, and propagates the sub-generator's return value as the
expression's value. How much of that NilPy's generator machinery can support is
the actual question — a partial implementation that forwards values but drops
the return value would be **silently wrong**, which is worse than the current
refusal. Establish what the generator implementation can carry before choosing
scope, and if the full semantics are out of reach, say so in the ticket and keep
refusing rather than half-landing it.

## Relationship to the version claim

[[feature-n-sys-version-info-implementation-and-the-probe-suite]] ships a test
asserting this is refused — as a **tripwire on the 3.9 claim**, not as a wish
that it stay broken. Fixing this should trip that test by design; whoever lands
the fix updates it and re-checks whether 3.9 is still the right number.

## Gate

`make test-nilpy` green + self-host byte-identical + cross. Plus the repro
above, and a test that pins the two behaviours a re-yield loop would get wrong:
the sub-generator's return value reaching the `yield from` expression, and
`send()` reaching the inner generator.
