---
track: A
prio: 65
type: bug
---

# NilPy `and` / `or` / `in` / `is` do not work in a CALL ARGUMENT

Found 2026-07-20 while integration-testing the f-string work. **Pre-existing**
— f-strings only made it much easier to hit, because every hole becomes a call
argument.

## Repro

```python
d = {"a": 1}

def show(b: bool) -> None:
    print(b)

show(not (1 > 2))        # OK    — Pascal has `not`
show(1 > 2 and 2 > 1)    # error: expected comma or close parenthesis
show("a" in d)           # error: expected comma or close parenthesis
```

Directly, and inside `print(...)`, all three are fine:

```python
print("a" in d)          # True
b = "a" in d             # True
```

## Cause

NilPy's Python precedence chain — `PyParseBoolExpr` -> `PyParseBoolAnd` ->
`PyParseBoolNot` -> `PyParseIsCmp` (which is where `in` / `is` and the
pycontains/pydictcontains dispatch live) — is entered only from NilPy
statement contexts: assignments, `print`, `if`/`while` conditions,
`PyParseStatement`. A CALL's arguments are parsed by the shared parser's
`ParseExpr`, which knows Pascal's `in` (set membership) and Pascal's `and`/`or`
precedence, and neither matches Python.

`not` survives only because Pascal happens to spell it the same way at a
compatible precedence.

Filed Track A: the fix is in `parser.inc`'s argument parsing, which Track N
must not edit.

## Shape

When `PyExprMode` is on, a call argument should be parsed by the NilPy chain
rather than by `ParseExpr` — the same delegation `PyParseListLiteral` and
`PyParseStrMethod` already use, where the shared parser knows only WHERE the
form is legal and pyparser.inc decides what it means.

## Why it matters

Every f-string hole is a call argument (`pystr_of(<expr>)`), so
`f"{name in d}"` and `f"{a and b}"` fail today while `print(name in d)` works
— a confusing split for anyone writing NilPy. uforth has both forms
throughout.

## Gate

`make test` + self-host byte-identical, `test-nilpy` green, and the three
`show(...)` lines above matching CPython.
