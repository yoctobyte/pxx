---
track: N
prio: 15
type: bug
blocked-by: []
summary: "`\"a\" < 3` with two LITERALS raises `unsupported operand type(s) for this operator` where CPython names both types. The dynamic shape already matches CPython exactly; only the statically-proven clash — where the compiler knows MORE — reports less."
---

# A statically clashing operand pair refuses without naming the types

```python
"a" < 3      # CPython: TypeError: '<' not supported between instances of 'str' and 'int'
             # pxx:     TypeError: unsupported operand type(s) for this operator
```

The same comparison through variables is already byte-identical to CPython:

```python
def f(x): return x
f("a") < f(3)   # both: TypeError: '<' not supported between instances of 'str' and 'int'
```

Found 2026-08-15 while resolving
`bug-nilpy-comparing-none-with-a-number-answers-instead-of-raising`, whose test
had to exclude this one row.

## Where

Two literals never reach `pylt_v`/`pyvar_gt`. `IRPyNumStrClash` proves the clash
at compile time and the arm emits `PyUnsupportedOperandError` (pylib), a
procedure that takes no arguments and therefore cannot name anything. The
runtime path answers better than the static one precisely because it can see
the operands.

The mildly funny shape of it: the compiler has MORE information here (both types
are known at compile time, which is why it took this arm at all) and produces a
WORSE message. Ordinary "one concept, two mechanisms" — the informative wording
lives in only one of them.

## Fix sketch

`PyOrdCheck`'s wording is already the one CPython uses; the static arm needs the
two type names passed to a raiser that takes them, e.g.
`PyOperandClashError(op, lname, rname)` with all three as IR string constants
the lowering site already has (it knows the operator token and both `ASTTk`s).
`PyUnsupportedOperandError` stays for the arms that genuinely have no operand
types to name (a missing arithmetic dunder).

Same treatment likely applies to the arithmetic clashes (`"a" + 3` and friends)
that share the raiser — check them together rather than one operator at a time.

## Gate

`"a" < 3`, `3 > "a"`, and the arithmetic siblings diffed against CPython, plus
the dynamic rows of `test_nilpy_none_comparison_raises` unchanged.
