---
track: A
prio: 40
type: bug
status: rejected
---

# NilPy: subscripting a string LITERAL is a parse error

Found 2026-07-20 while writing the regression test for
[[bug-a-nilpy-one-char-string-literal-is-a-char]].

## Repro

```python
print("abc"[1])     # error: unexpected token (  — CPython prints b
```

A string in a variable subscripts fine (`s = "abc"; print(s[1])`), so this is
the literal base only.

## Cause (suspected)

`PyMakeStrIndex` is reached from the lvalue postfix path, which a literal never
enters — the same asymmetry `PyParseStrMethod` needed its ParseFactor wrapper
for (`"a".upper()` works because of that wrapper). The subscript suffix likely
needs the same treatment at factor level.

## Gate

`make test` + self-host byte-identical, `test-nilpy` green, the repro matching
CPython — plus a negative index (`"abc"[-1]`) and a chained one
(`"abc"[1].upper()`).

## Log

- 2026-07-20 — DUPLICATE of [[bug-nilpy-subscript-on-literal]], filed 2026-07-19
  with the same repro and the same root-cause reading. Rejected in favour of the
  older ticket; nothing here is lost.
