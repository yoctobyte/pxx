---
track: N
prio: 75
type: bug
blocked-by: []
summary: "`i < n` with either side a variant heap-allocates a 32-byte block per EVALUATION — 91466 allocations for 100000 iterations, linear. Variant arithmetic in the same loop allocates nothing, so this is the comparison path alone."
---

# A variant comparison heap-allocates a box per evaluation

Measured 2026-09-15 at `4452ec0631a97c02` with `-dPXX_ALLOC_CENSUS`, 100000
iterations each, one variable changed at a time:

| loop body | 32-byte allocations |
| --- | --- |
| variant **arithmetic** only, bound annotated | none (below the census threshold) |
| variant **comparison** only (`if i < v`) | **91466** |
| neither (fully annotated control) | none |

One block per comparison EVALUATED, linear in the iteration count. Variant
arithmetic in the identical loop allocates nothing, which is what isolates this
to the comparison path rather than to variants in general.

The commonest way to meet it is not an explicit comparison at all — it is a
`while` loop whose BOUND is an unannotated parameter:

```python
def hot(p, n):          # n is a variant
    i = 0
    while i < n:        # <- one heap allocation per iteration
        ...
```

Annotating `n: int` takes the same program from 91466 allocations to 39.

## Corroborated by a second instrument that shares nothing with the first

The lekkerzeilen seat, sampling a pxx binary's leaf PC through the `.map`, found
the top leaves of an unannotated arithmetic loop to be `pycmp_v`,
`PXXPromoVarCmpTry`, `PXXPromoToVariant`, `PyOrdCheck`, and `PXXAlloc`/`PXXFree`
together at 16.7% — in a loop whose source allocates nothing. An allocation
census and a sampling profiler agreeing on the same mechanism is the
two-independent-readings bar, and neither was looking for this.

## What it cost to find, which is the reason it is filed rather than fixed

It contaminated the benchmark it was hiding in. A variant-versus-double
arithmetic measurement written with `while i < n` and an unannotated `n` reports
**25.8x**; the same comparison with the bound annotated and no hoistable work
reports **156x**. The allocation was most of the reported cost of the thing it
was not measuring. Anyone benchmarking variant code must annotate the loop bound
or they are timing the allocator.

## Not yet established

Whether the box is the promoted operand, the boolean result, or scratch for
`PXXPromoVarCmpTry`; whether a comparison against a CONSTANT takes the same path
as one against a variable; and whether the non-ordered comparisons (`==`, `!=`)
allocate too — only `<` was measured. All three are cheap to settle with the
same census and should be settled before the fix, because they decide whether
this is one allocation site or a family.
