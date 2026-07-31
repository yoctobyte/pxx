---
summary: "pyeval: `**` is not in the expression grammar — `2 ** 70` is a parse error inside exec()"
type: feature
track: N
prio: 30
---

# `**` is missing from pyeval's expression grammar

- **Type:** feature (NilPy runtime — `compiler/builtin/pyeval.pas`) — **Track N**
- **Opened:** 2026-07-31 by Track B, exercising [[feature-lib-pyexec]] from a
  `.npy`.

## Repro

```python
exec("push(2 ** 10)", env)
```

```
pyeval: expected , or ) in call
```

The diagnostic points at the call rather than at the operator, because the
expression parser stops at the first `*` and then finds a second one where it
expects `,` or `)`.

## Why it is worth having

`**` is how Python spells the thing a bit-twiddling corpus reaches for
constantly — masks and cell widths are `2 ** 64`, `2 ** 32 - 1`. The
interpreter already carries arbitrary-precision integers (the bignum tail
landed, so `2 ** 70` has somewhere to go); only the grammar is missing.

Bounded: a right-associative binary operator binding tighter than unary minus,
over the integer path that already promotes on overflow. Python's `**` also
accepts a float exponent, which can be refused loudly at first rather than
guessed at.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` covering integer
`**` including a result past 64 bits and the right-associativity of
`2 ** 3 ** 2`, diffed against CPython.
