---
track: N
prio: 35
type: bug
---

# `pypow_v`'s integer path silently wraps past 64 bits instead of promoting

```python
print(2 ** 70)
```

```
CPython: 1180591620717411303424
pxx:     0
```

Found 2026-07-31 while gating [[feature-pyeval-power-operator]] (which only
needed exec()'s missing `**` grammar wired to the existing `pypow_v`, and did
that). This is a separate, pre-existing gap in `pypow_v` itself
(`compiler/builtin/pylib.pas`), present in the ordinary COMPILED NilPy `**`
too (`parser.inc`'s `ParseFactor` lowers to the same `pypow_v`) — not
introduced by, or specific to, the exec() path.

## Cause

`pypow_v`'s integer branch does repeated squaring in plain `Int64`:

```pascal
n := pyvar_to_int(b);
ibase := pyvar_to_int(a);
ir := 1;
while n > 0 do
begin
  if (n and 1) = 1 then ir := ir * ibase;
  ibase := ibase * ibase;
  n := n shr 1;
end;
```

No overflow check anywhere in the loop — unlike `pymul_v`/pyeval's own
`PyIMul`, which detect an overflowing `*` (dividing back through and
comparing) and promote to the bignum runtime (`PromoOp`/`PXXPromoMul`) when
it does. `pypow_v` never had that check, so a big-enough integer result just
wraps mod 2^64 with no error and no promotion.

## Shape of a fix

Mirror `PyIMul`'s overflow probe (`r := ia * ib; if (ia <> 0) and (r div ia
<> ib) then <promote>`) inside `pypow_v`'s squaring loop, upgrading to the
`PXXPromo*` primitives (`PXXPromoInit`/`FromVariant`/`Mul`/`ToVariant`/`Clear`
— see `pyeval.pas`'s `PromoOp` for the exact calling shape) once either
operand overflows. Requires `pylib.pas` to `uses promoint` (it currently
does not depend on that unit at all — check for a circularity before adding
it; `pyeval.pas` already uses both without issue, which suggests none, but
verify).

## Gate

`make test-nilpy` + self-host byte-identical, plus `2 ** 70`, `2 ** 100`, and
a negative-base odd/even exponent case (`(-2) ** 65`, `(-2) ** 66`) diffed
against CPython, through BOTH the compiled `**` and `exec("... ** ...")`.
