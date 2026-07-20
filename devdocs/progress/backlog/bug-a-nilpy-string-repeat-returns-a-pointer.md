---
track: A
prio: 60
type: bug
---

# NilPy: `s * n` on a string returns a POINTER, silently

Found 2026-07-20 sweeping NilPy's operators against CPython.

```python
s = "hello"
print(s + " " + "world")   # hello world      correct
print(len(s))              # 5                correct
print(s * 2)               # 8577376          WRONG — CPython: hellohello
```

Silent. `*` on a string is a type error in Pascal, but here the string HANDLE
is multiplied as an integer and the product printed as a number.

The list form is different and honest: `[0] * 3` fails to compile
("len(xs)" then errors), so only the string case is silent.

## Why Track A, not N

Checked the file ownership before filing a fix: `pyparser.inc` owns only the
BITWISE and BOOLEAN layers (`PyParseBitOr` down to `PyParseIsCmp`). The
comparison and arithmetic layers are the shared parser's `ParseSimpleExpr` /
comparison chain in `parser.inc:10781`, so the node is built — and its
semantics chosen — outside Track N's files. The fix belongs there, gated on
`PyExprMode` the way other NilPy-specific behaviour already is.

This is the same boundary that put `bug-a-nilpy-floordiv-and-modulo-wrong-for-negatives`
and `bug-a-nilpy-and-or-in-unavailable-in-call-arguments` in Track A: NilPy's
own precedence chain sits ABOVE the arithmetic, not around it.

## Shape

Python's `str * int` (and `int * str`) repeats. Either:

- lower it to a `pystr_repeat(s, n)` pylib function — the no-hook route
  `bytearray`, `min` and `max` already take, since the operands' types are
  known at the binop; or
- reject it with a diagnostic, which is still strictly better than a wrong
  number.

Do the same for the list form (`[0] * n`, 1 uforth site, currently a clean
error) if it is cheap at the same time — it is the idiom for preallocating a
slot array.

## Priority

p60 rather than higher: 1 uforth site, and the wrong value is a large
implausible number rather than a subtly wrong one, so it is likely to be
noticed. But it IS silent, which is the category that earns a ticket rather
than a note.

## Gate

`test-nilpy` green with the three lines above diffed against CPython +
`--tier quick` + self-host byte-identical + `make fpc-check`.
