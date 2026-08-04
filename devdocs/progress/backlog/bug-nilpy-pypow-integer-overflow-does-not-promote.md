---
track: N
prio: 35
type: bug
status: working
owner: claude-AN
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


## 2026-08-04 — the premise about `pymul_v` is WRONG, and the real fork is a size trade-off

This ticket says `pypow_v` has no overflow check "unlike `pymul_v`/pyeval's own
`PyIMul`, which detect an overflowing `*` … and promote". Half of that is false,
and it is the half that would have made the fix cheap.

**`pymul_v` does NOT promote.** Its numeric arm (`pylib.pas`) is a plain Int64
multiply with no probe at all:

```pascal
r^.VType := 2;
r^.Payload := pyvar_to_int(a) * pyvar_to_int(b);
```

Only **pyeval's** `PromoOp`/`PXXPromoMul` promote, and pyeval is the unit that
`uses promoint`. Measured, not read: routing `pypow_v`'s squaring loop through
`pymul_v` over variants was implemented and changed **nothing** — `2 ** 70`
still printed 0. Reverted rather than left in, since an inert change is how a
wrong premise gets a foothold.

### So the fix costs something, and the choice is a real one

1. **`pylib uses promoint`** and the probe goes in `pypow_v` as this ticket
   describes. Correct and complete — it also fixes `pow(a, b)`, which routes to
   the same place. But `promoint` is what the DCE note measures at **35KB → 92KB**
   ([[project_promotable_int_stages123]]), and pylib is linked into EVERY NilPy
   program, so every binary pays it whether or not it ever raises anything to a
   large power. On a ~1.27MB NilPy binary that is roughly +4%.
2. **Put the promoting power in pyeval** (which already uses `promoint`) and
   point the `**` lowering at it — `PyMakePow` in `pyparser.inc` is now the ONE
   place that chooses the callee, so this is a one-line redirect. Costs nothing
   for programs that do not link pyeval. But `pow(a, b)` — pylib's function —
   still wraps unless it is redirected too, and it cannot reach pyeval, so the
   two spellings of the same operation would diverge. That asymmetry is worse
   than the bug for anyone who hits it.
3. **Raise OverflowError instead of promoting.** Cheap, honest, no new
   dependency, and strictly better than silently printing 0 — but it is a
   deliberate divergence from Python, where `2 ** 70` simply works.

Route 2's asymmetry is the thing that makes this a judgement call rather than a
task: option 1 is the only one where `2 ** 70` and `pow(2, 70)` agree, and it is
the one that costs every program 57KB.

**Not implemented.** Recorded here rather than guessed at; the ticket keeps its
priority and its gate. Note `pow(base, exp, mod)` (the three-argument modular
form, added today) is unaffected either way — it never builds the full power.
