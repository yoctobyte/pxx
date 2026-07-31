---
track: N
prio: 45
type: feature
---

# The `**` and `/=` operators and `divmod()` are missing

```python
print(2 ** 10)     # error: expected expression
print(divmod(7, 2))# error: undefined variable (divmod)
```

`**` does not parse at all, so it takes the whole file with it — a program that
computes anything with an exponent cannot be compiled. It is ordinary Python
(and `2 ** 0.5` is the idiomatic square root), which makes it the more
important of the two.

`divmod` is a plain builtin returning a tuple; `//` and `%` are both already
correct on negative operands (`-7 // 2 == -4`, `7 % -2 == -1`), so it is those
two results in a tuple.

`/=` is missing too, and independently of `**`:

```python
f = 1.5
f /= 2            # error: expected expression
```

Every other augmented assignment works and matches CPython exactly — `+=`,
`-=`, `*=`, `//=`, `%=`, `&=`, `|=`, `^=`, `<<=`, `>>=`, over ints, floats,
strings, lists and a dict element. So `/=` is one missing token mapping, not a
missing mechanism: `/` itself works.

Semantics to match: integer `**` with a non-negative exponent is exact (pxx has
promotable ints, so `10 ** 20` should be exact rather than a double); a
negative exponent yields a float; `0 ** 0` is 1; float bases go through the
libm path.

Found by the numeric sweep against CPython. Everything else in that sweep
matched exactly, including floor/mod sign behaviour on negative operands,
shifts, `~`, bitwise ops, `int(str, base)`, and 64-bit boundary values —
`round(2.675, 2)` is the only other divergence (CPython 2.67, pxx 2.68, which
is the binary-representation subtlety and belongs to
[[bug-nilpy-large-float-str-overruns-into-garbage]]'s formatting question).

## Gate

`make test-nilpy` + self-host byte-identical, plus `**` over int/float bases
and negative/zero exponents, and `divmod` over positive and negative operands,
diffed against CPython.

## Log
- 2026-07-31 — resolved, commit b4222faaf694c64f7c472c787c2df7d507245269.
