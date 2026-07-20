---
track: A
prio: 55
type: bug
---

# NilPy: `s = "x" * 300` infers s as INT, then no overload of len matches

Found 2026-07-20 while landing [[bug-nilpy-string-local-truncates-at-255]].
Pre-existing — reproduces on the compiler built before that change.

## Repro

```python
s = "x" * 300
print(len(s))
```
```
Mismatch in MatchProcCall: name = len, nArgs = 1
  arg[0] = 1                      <- tyInteger
pascal26:2: error: no overload of len matches these arguments
```

`print("x" * 300)` alone is CORRECT, so the repeat itself lowers fine — only
the inferred type of a local holding its result is wrong.

## Cause (suspected)

The AST-based local typing takes ASTTk of the assignment's RHS, and the `str *
int` binop node is tagged with the arithmetic result (tyInteger) rather than
the string type — ParseTerm's tkStar branch types by the operand kinds and has
no NilPy repeat case. `str * int` and `int * str` both need to yield the string
type under PyExprMode, as does `list * int`.

## Note

The diagnostic also dumps `Mismatch in MatchProcCall: ...` internals to stdout
before the error line — that part is
[[bug-overload-mismatch-dumps-internals-to-stdout]].

## Gate

`test-nilpy` green + `--tier quick` + self-host byte-identical, with
`s = "x" * 300`, `s = 3 * "x"`, `xs = [0] * 4` and their `len()` matching
CPython.

## Log
- 2026-07-20 — resolved, commit 702ffc6e.
