---
track: N
prio: 60
type: bug
owner: unassigned
blocked-by: []
summary: "`def f(x: int): x = x + 1; x /= 2` is refused with `annotate the type / too dynamic [a=28 b=19]` — a promotable int (28) joined against a double (19). Ordinary CPython code, refused at compile time. One rebind of either kind alone is fine; it is the PAIR that has no join."
---

# Rebinding an int parameter twice across the float boundary is refused

- **Type:** bug (Track N) — a compile refusal of working CPython code.
- **Found:** 2026-08-27 while resolving
  [[bug-n-augmented-true-division-does-not-widen-an-annotated-int-parameter]],
  whose fix made every single-rebind shape correct and left this one.
- **Measured:** identical at pinned **v383** (`18392d1d3181`) and at HEAD — the
  sibling fix changed neither the message nor the outcome.

## Repro

```python
def two(x: int):
    x = x + 1       # int + int can overflow -> a PROMOTABLE int (kind 28)
    x /= 2          # ...and true division wants a double (kind 19)
    return x
print(two(5))       # CPython 3.0
```

```
pascal26:3: error: Nil Python: annotate the type / too dynamic [a=28 b=19]
```

Either rebind ALONE is fine: `x = x + 1` alone returns 6, and `x /= 2` alone
returns 2.5 (as of the sibling fix). It is the pair that has no join.

## Where it comes from

`x = x + 1` on an int notes `tyPromoInt64` — deliberately, so an accumulator
stays exact past 2^63 — and `/=` then notes `tyDouble`. The widening join has no
answer for that pair and reports "too dynamic" rather than picking one.

The obvious answer is **variant**, which is what `PyWidenBinding` already gives
for an ordinary int-vs-float rebind and what a promo value boxes into anyway
(`VT_PROMO_INT64` carries the exact decimal). Whether the join belongs in
`PyWiden`, in `PyWidenBinding`, or at the promo-specific site is the thing to
measure — `TypeIsPromoInt` is deliberately excluded from `PyWidenBinding`'s
numeric arm today, and that exclusion is what routes this pair to the error.
Read that exclusion's reason before changing it.

## Gate

`two(5)` prints `3.0`, plus the same shape on a plain LOCAL (which must keep
whatever it does today) and on an accumulator that genuinely needs the promo
width (`x = x + 1` in a loop past 2^63, no float in sight — must stay exact).
