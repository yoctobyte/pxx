---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`def open(x)` in a .npy is silently ignored — the builtin runs and raises FileNotFoundError instead of calling the user's function. Python lets a def shadow any builtin, and 13 of the 17 builtins swept get this right; open's intercept never asks. Silent wrong behaviour, not a refusal."
---

# A user `def open()` is silently ignored

```python
def open(x):
    return "USER:" + x

print("got", open("f"))
```

CPython prints `got USER:f`. pxx raises `FileNotFoundError: f` — the builtin
intercept claimed the call and the user's function was never reached. No
diagnostic.

Found 2026-08-13 sweeping every intercepted builtin for the shadowing question
while examining [[decide-nilpy-builtin-vs-pascal-unit-name-resolution]].

## The sweep that found it

`def <name>(x): return "USER"` then `<name>(3)`, 17 builtins:

| result | names |
| --- | --- |
| user def wins — CPython's answer | len, sum, sorted, max, min, format, input, str, abs, round, enumerate, callable, repr |
| refused with a diagnostic | print (it LEXES to a token), zip, type |
| **silently ignored** | **open** |

So the majority is right and this one is not. The three refusals are their own
(smaller) problem — a diagnostic is honest, a wrong answer is not.

## Cause

Each intercept decides the shadowing question independently, with a different
mechanism: a lexer keyword (`print`), `PyUserShadowsProc` (`enumerate`),
`FindSym(name) < 0` (`input`, `type`), `ProcUnitIdx = -1` (`format`). The `open`
arm — `else if isNilPy and (name = 'open')` in parser.inc — has NO guard at all.

That is the "one concept, N independent sites" shape this repo keeps paying for
(devdocs/dev/normalise-dont-special-case.md): fix `open` and the next intercept
added will forget again.

## Shape of a fix

The one-line version is to give the `open` arm the same guard its neighbours
have. The right version is one predicate every intercept calls — "does the
program's own code bind this name?" — which is what
[[decide-nilpy-builtin-vs-pascal-unit-name-resolution]] is deciding the shape
of. Do the one-liner if that ticket is still open; do not add a fifth
mechanism.

## Gate

The sweep above as a `.npy` diffed against CPython: a `def` of each intercepted
builtin, called, plus the builtin still working in a program that does NOT
define it. `zip`/`type`/`print` may stay refusals in this ticket — they are
diagnostics, not wrong answers — but say so in the test.
