---
track: N
prio: 45
type: bug
commit: 1ad845c6e
blocked-by: []
summary: "`int(7/2)` printed 4615063718147915776 — 3.5's bit pattern read as an integer. int() took its argument's type from LastExprTk, a side channel that after an operator expression holds the last FACTOR's type, so the float arm was skipped. `x = 7/2; int(x)` was correct."
---

# `int()` of a division reads the double's bits

```python
print(int(7 / 2))        # CPython 3     pxx 4615063718147915776
print(int(3.5))          # 3             — correct
x = 7 / 2
print(int(x))            # 3             — correct
```

Silent, and on `int(a / b)`, one of the most ordinary lines in Python. Found
2026-08-15 by a CPython differential sweep of numeric constructs.

## Cause — the value was never wrong, the side channel was

The int() intercept chooses its lowering per argument type: the -203 Trunc
intrinsic for a float, -200 for everything else (which handles str, variant,
int, bool). It asked **`LastExprTk`** rather than the argument NODE's own type.
After an operator expression `LastExprTk` holds the last FACTOR's type — the
`2` of `7 / 2`, an integer — so the float arm was skipped and -200 took the
double's payload as an integer.

An IDENT leaves `LastExprTk` agreeing with the node, which is exactly why the
two-line spelling was right and the one-liner was not, and why nothing in the
corpus caught it.

`print(7 / 2)` was correct throughout: the division and its node type were
always right. Only the consumer read the wrong source —
`project_variant_store_kind_came_from_the_ast_not_the_value`'s rule, one level
up: **take the kind from the value, not from a side channel.**

## Fixed at the source, because int() was not the only consumer

The first fix read the node's type in the int() arm. Sweeping the neighbours
then found the same defect in **`float()`** (`float(7/2)` printed
4.612811918334231e+18) and in **`round()`** (`round(2/3, 3)` ignored its ndigits
and printed 0.6666666666666666), each dispatching on `LastExprTk` the same way —
and any future consumer would have inherited it.

So the real fix is one line at each of the two operator loops: `ParseTerm` and
`ParseSimpleExpr` now leave `LastExprTk` holding the type of the node they just
built. Nothing else wrote it after `ParseFactor`, which is why "the type of the
expression I just parsed" and "the type of the last factor" had silently been
the same question everywhere except across an operator.

Both spellings are kept in the int() arm — the node test first — since a
consumer asking the node directly is right regardless of who else writes the
side channel.

## Gate

`test/test_nilpy_int_of_an_expression.npy` (+`.expected`, in the Makefile),
byte-identical to CPython: `int()` over a division, a true-division by 1, a
float-by-int division, a negative division, a multiplication, an addition and a
subtraction; via a named local as the control; nested `int(int(x)/1)`; over a
call result and `abs()`; over `//`, `%` and `**`; the str and radix forms; bool;
`round()`; a variant argument; a bignum (whose arbitrary precision must
survive); and the raw values themselves. `gate.sh quick` GREEN. No pin —
frontend-only.
