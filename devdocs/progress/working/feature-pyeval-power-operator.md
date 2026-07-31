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

## FIXED (this session) — grammar landed; the >64-bit case is a separate, pre-existing gap

Added `ParsePower` to pyeval.pas between `ParseUnary` and `ParsePrimary`,
mirroring the compiled frontend's own `**` (parser.inc's `ParseFactor`):
right-associative (the exponent recurses into `ParseUnary`, not `ParsePower`,
so `2 ** -1` parses and `2 ** 3 ** 2` still right-associates), binds tighter
than unary minus (`-2 ** 2` = `-4`), and lowers to the same `pypow_v` pylib
already exposes. Verified against CPython: `2**10`, `2**3**2`, `-2**2`,
`2**-1` all match exactly, and the existing `lib_pyexec.npy` corpus test is
unaffected.

**"a result past 64 bits" is NOT met, and was found to be untrue of the
ALREADY-EXISTING compiled-frontend `**` too** — measured, not assumed:
`2 ** 70` prints `0` (silent Int64 wraparound) through the ordinary compiled
NilPy path, not just through pyeval. `pypow_v`'s integer branch
(pylib.pas) does plain `Int64` repeated squaring with no overflow check —
unlike `pymul_v`/`PyIMul`, which detect overflow and promote to the bignum
runtime, `pypow_v` never did. Fixing that needs `pypow_v` to call the
`PXXPromo*` primitives directly (the pattern `pyeval.pas`'s own `PromoOp`
already uses) — straightforward in shape, but `pylib.pas` does not currently
depend on `promoint.pas` at all, so it is a real (if bounded) follow-up, not
a one-line addition, and it fixes the COMPILED frontend's `**` too, not just
this exec() path. Left open rather than silently narrowing the gate to
match what shipped.

Regression: `test/test_nilpy_pyeval_power_operator.npy` (the four cases that
now work; the >64-bit case is deliberately not asserted here since it does
not yet match CPython).

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` covering integer
`**` including a result past 64 bits and the right-associativity of
`2 ** 3 ** 2`, diffed against CPython.
