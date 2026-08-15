---
track: U
prio: 20
type: decide
blocked-by: []
summary: "`for d in [1, 2.5]` — FPC 3.2.2 prints `1.00 0.00`, dropping the 2.5; pxx prints `1.00 2.50`. Shipped as the correct answer rather than copied, because losing a written value is a defect and not a semantic choice. Confirm, or put FPC's answer behind --strict-fpc."
---

# `for d in [1, 2.5]`: match FPC's dropped value, or keep the right one?

Measured 2026-08-15 while fixing
[[bug-p-for-in-over-a-float-array-constructor-iterates-once-with-zero]].

```pascal
var d: Double;
for d in [1, 2.5] do Write(d:0:2, ' ');
```

| | |
| --- | --- |
| FPC 3.2.2 | `1.00 0.00` |
| pxx (as shipped today) | `1.00 2.50` |

FPC's mixed integer/float array constructor **drops the 2.5**. Not a rounding
difference and not an order difference — the value the source wrote does not
come out. (The ticket that led here predicted "FPC promotes"; it does not, and
that prediction is what made this worth measuring rather than assuming.)

## The fork

This repo's default is the reference implementation, with deviations behind
`--strict-*`. Applied literally, pxx should print `1.00 0.00`.

Against that: the whole defect being fixed in the same commit was a float
constructor that silently answered `0.0`, and the argument for fixing it was
that a silent wrong value is the expensive kind. Reproducing FPC here would
reintroduce the same failure mode by hand, in the one row a reader is least
likely to test.

## Options

1. **Keep `1.00 2.50` (shipped, recommended).** A written value always comes
   out. Documented in `test/test_forin_nonordinal_array_ctor.pas` at the row
   itself, so it is not silent. Costs: one more entry in the deliberate-
   divergence list; a program relying on FPC's zero (nobody writes that on
   purpose) behaves differently.
2. **Match FPC exactly**, and gate the correct answer behind a flag. Costs:
   pxx knowingly emits a wrong value by default.
3. **Refuse the mixed constructor** with a diagnostic ("mixed integer and float
   array constructor: write 1.0"). Neither compiler does this, and it breaks
   source FPC accepts — but it is the only option where nobody gets a silently
   wrong number.

## Recommendation

Option 1, which is what is shipped. Option 3 is a defensible second if the
project would rather refuse than diverge; it needs a `--strict-*` escape and a
sweep of the corpora for mixed constructors before it could land.

Nothing is blocked on this — the row is asserted either way, so a decision is a
one-line change to the test plus the arm in `parser.inc`.
