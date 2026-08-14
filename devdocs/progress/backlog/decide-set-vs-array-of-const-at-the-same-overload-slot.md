---
track: U
prio: 30
type: decide
summary: "When an overload set has both a `set of T` and an `array of const` parameter at the SAME slot, what should `f([x])` mean? Measured: FPC 3.2.2 is itself uses-order dependent and flips answer, and pxx flips on a different order — so there is no reference behaviour to copy. Rare, and nothing in the tree hits it; filed because the fix next door made the question visible, not because anything is broken."
---

# `[x]` where one overload takes a set and another takes `array of const`

- **Type:** decision — **Track U**. Escalated rather than guessed while closing
  [[bug-a-array-of-const-literal-does-not-match-in-a-cross-unit-overload-set]].
- **Nothing is broken today.** The reported bug is fixed and its shape matches
  FPC. This is the residual corner that fix made visible.

## The shape

Two units, both exporting `k` with `overload`: one takes `TDays = set of TDay`,
the other takes `array of const`. Then:

```pascal
k([dTue]);     { a set literal? or a one-element TVarRec vector? }
```

Both readings are well-typed. The parser must choose BEFORE overload
resolution, because the choice determines how the brackets are parsed at all.

## Measured — and the reference implementation does not settle it

| uses order | FPC 3.2.2 | pxx |
| --- | --- | --- |
| set-unit first, array-of-const unit last | `k-aoc: n=1` | `k-aoc: n=1` |
| array-of-const unit first, set-unit last | **`k-set: dTue`** | `k-aoc: n=1` |

**FPC flips its answer with uses-clause order**, which means "be FPC-faithful"
has no single answer to be faithful to. pxx is at least consistent — it always
reads the brackets as `array of const` once a candidate offers one — but it
differs from FPC on the second row.

## The options

1. **Leave it** (today). pxx is order-INDEPENDENT and picks `array of const`.
   Defensible on its own terms: order-independence is a better property than
   matching an order-dependent reference, and the `--strict-fpc` umbrella exists
   for cases where bug-for-bug parity is actually wanted.
2. **Match FPC row for row**, order dependence included. Costs a rule nobody can
   explain and that a user cannot predict.
3. **Refuse it as ambiguous**, and require a cast or a distinct name. Loudest,
   and arguably the honest answer for a construct where the reference
   implementation contradicts itself — but it would reject programs FPC
   compiles, which the compat rule normally forbids.

My recommendation is **1**, with this ticket as the record and a row in the
dialect notes if it stays. Option 3 is tempting and is the only one that never
silently does the wrong thing, but "rejects a program FPC accepts" is a real
cost for a corner with no known user.

## What would change the answer

A real program that declares both at the same slot. None is known — this was
constructed to probe the boundary of the fix next door, and the regression test
there deliberately asserts only the unambiguous form.
