---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`\"%.1f\" % 0.15` answers 0.2 where CPython answers 0.1, and 0.45 answers 0.4 where CPython answers 0.5: scaling the fraction by a power of ten lands exactly on .5 for values whose binary expansion is just below or just above it, so the formatter rounds a tie that does not exist — and gets it wrong in BOTH directions. Needs exact decimal digit generation, not a rounding tweak"
---

# Float formatting manufactures ties by scaling

- **Type:** bug (silent wrong value, last digit) — **Track N**
- **Found:** 2026-08-12, while fixing
  [[bug-nilpy-float-formatting-rounds-half-toward-zero-not-half-even]] — that
  ticket fixed the EXACT ties (`7.5` at `.0f`); this is the family underneath.
- **Pre-existing:** identical on `stable_linux_amd64/default/pinned`, verified.

| value | `%.1f` / `%.2f` pxx | CPython |
| --- | --- | --- |
| `0.15` | `0.2` | `0.1` |
| `0.35` | `0.4` | `0.3` |
| `0.45` | `0.4` | `0.5` |
| `1.115` | `1.12` | `1.11` |

Note the two directions: `0.15` is rounded UP where CPython rounds down, and
`0.45` is rounded DOWN where CPython rounds up. So this is not an off-by-one
rule that a different tie-break would fix.

## Why

`0.15` as a double is `0.1499999999999999944488848768742172978818416595458984375`
— *below* the midpoint, so CPython's `.1f` gives `0.1`. `PyFmtFixed` computes
`(0.15 - 0) * 10`, and that product is **exactly 1.5**: the multiplication
rounds the error away and creates a tie that the value does not have. The
half-even rule then applies to a tie that should never have been asked about.
`0.45` is *above* its midpoint (`0.450000000000000011...`) and the same
multiplication flattens it to `4.5`, where half-even sends it down.

The fix is not in the tie-break. CPython and glibc convert the double's exact
binary value to decimal digits with arbitrary precision and then round the
DIGIT STRING; no float arithmetic is involved, so no tie is ever manufactured.
Anything short of that keeps a family of last-digit disagreements.

## Scope note

Only the last digit, and only for values that sit within one ulp of a decimal
midpoint — but a formatted price or percentage is exactly where those live, and
`0.15` rounding to `0.2` is the kind of thing a spreadsheet comparison catches
and no test does.

`PyFmtExp` and the `%` (percent) form share `PyFmtFixed`, so they inherit it.

## Gate

A `.npy` diffed against CPython: the four rows above plus a sweep of
`x/100` for x in 5..995 step 10 at `.1f` and `.2f` (which is dense in
midpoint-adjacent values), the exact-tie rows from the sibling ticket still
correct, and the same values through `"%.Nf" %`, an f-string spec, and the
percent form.
