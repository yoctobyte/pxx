---
track: N
prio: 65
type: bug
---

# `str(3 % 2.5)` prints the double's BIT PATTERN

```python
print(3 % 2.5)        # CPython: 0.5    pxx: 0.5      <- correct
print(str(3 % 2.5))   # CPython: 0.5    pxx: 4602678819172646912
x = 3 % 2.5
print(str(x))         # CPython: 0.5    pxx: 4602678819172646912
```

`4602678819172646912` is `0.5` reinterpreted as an Int64. `str(3 / 2)` and
`str(3.0 * 2)` are both fine, so it is specific to `%` (and `//`) with MIXED
int/float operands.

## Cause, already located

The parser types `a % b` with `TypeDivideResult(<left operand>)`, which ignores
a float RIGHT operand — so `3 % 2.5` is an integer-typed node at parse time.
ir.inc later notices the float operand, routes the node to `pyfloormod_f` and
retypes it `ASTTk[node] := Ord(tyDouble)` — but that is too late for `str()`,
which picked its overload at PARSE time from the integer type and therefore
binds the Int64 one.

`print(3 % 2.5)` is correct only because print reads the node type after
lowering.

## Fix direction

Type the node from BOTH operands at parse time, under PyExprMode only:
`tkDiv`/`tkMod` with either operand float yields float. Pascal's own `div`/`mod`
are integer-only, so guarding on PyExprMode keeps the Pascal dialect and the
self-host binary untouched. Then the ir.inc retype becomes a no-op agreement
rather than a correction.

Found while verifying the division-by-zero fix against the operator sweep — the
sweep wraps every case in `str(...)`, which is exactly what exposed it, and the
same reason it survived the plain `print` tests.

## Gate

`make test-nilpy` + self-host byte-identical, plus `str()`/`print()`/f-string
of `%` and `//` over every int/float operand pairing.
