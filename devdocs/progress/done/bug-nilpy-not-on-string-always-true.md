---
track: N
prio: 60
type: bug
---

# NilPy: `not s` on a string was ALWAYS True (silent wrong branch)

Found 2026-07-20 while adding one-line suites for the uforth drive. The guard
clause `if not token: return None` — uforth's single most common idiom — took
the wrong branch for every non-empty string.

```python
s = "abc"
if s: print("s truthy")          # correct
print(bool(s))                   # True — correct
if not s: print("not s -> True") # WRONG: fired for a non-empty string
```

## Root cause

`PyParseBoolNot` (pyparser.inc) special-cased ordinals (`not 5` -> `5 = 0`)
and booleans, and let everything else fall through to `AN_NOT` — which is
Pascal's BITWISE complement. Applied to a string that complements the string
HANDLE, which is never zero, so the result was non-zero and therefore truthy:
`not s` was True for every string, empty or not.

The existing code comment called non-ordinal `not` "its own question, filed
separately" — but no ticket was ever filed for it, so it sat as live silent
wrong behaviour rather than a known gap.

## Why it hid so well

`if s:` and `bool(s)` were both CORRECT — truthiness has a separate, working
path, and pylib even has a `bool(const s: AnsiString)` overload. Only the
`not` route was wrong, so any test that checked string truthiness the obvious
way passed. It also fails as a wrong BRANCH, never as a crash or a type error.

## Fix

A string is truthy when non-empty, so `not s` lowers to `Length(s) = 0`
(`AN_CALL` with `ASTIVal = -Ord(tkLength)` compared against 0). Covered by
`test/test_nilpy_truthiness.npy`, diffed against CPython and in the
`test-nilpy` gate.

## Still open, deliberately

`not <class>` and `not <variant>` still go through `AN_NOT` unchanged. Python's
object truthiness (`__bool__`/`__len__`) is a real design question rather than
an oversight, and no censused uforth site needs it. If it is picked up, note
that pylib already has `bool()` overloads for `TPyList` and `Variant` — the
work is selecting the right OVERLOAD from the frontend, which is why this fix
used `Length` directly instead.

## Gate

`make test-nilpy` green, `--tier quick` GREEN, self-host byte-identical,
fpc-check clean relative to HEAD.
