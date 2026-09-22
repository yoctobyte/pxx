---
track: N
prio: 75
type: bug
blocked-by: []
summary: "NOT REPRODUCIBLE AT HEAD, re-measured 2026-09-22, and CLOSED BEHIND A GUARD rather than on a bare negative. Originally: `i < n` with a variant operand heap-allocated a 32-byte block per EVALUATION, 91466 allocations for 100000 iterations. At HEAD all SIX comparison operators sit at 2-10 allocations per 100000 evaluations against a variant, and 727-818 for 600000 evaluations in the committed fixture -- which also settles the three questions this ticket said had to be answered before any fix: it is not a family, `==`/`!=` do not allocate either, and a constant bound behaves the same as a variable one. THE ROUTE WAS VERIFIED, not assumed: the loop bound is `mixed[0]` from a mixed list, which PXXDBG=n.locals reports as tk=22 where a plain int is tk=13 and a plain float tk=19 -- an unannotated PARAMETER is NOT a reliable variant, the compiler can narrow it, which is the probe error that nearly produced a false all-clear here. The instrument was positive-controlled at 185,433 allocations on a heavy program, and the new guard was shown to FAIL at a ceiling below its own floor. WHAT IS NOT ESTABLISHED: no source commit touched PXXPromoVarCmpTry/PyVarCompare since 2026-09-10, so the cause of the disappearance is unidentified and there is no old-binary control -- the claim is about the OBSERVABLE, not about a fix anyone can point to. Guard: test/nilpy_variant_comparison_allocates_nothing_per_evaluation.py, ceiling 3000 against a floor near 800 and a defect near 600000."
status: done
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

## 2026-09-22 — re-measured at HEAD: the observable is gone, and the three open questions are answered

The ticket said its three "not yet established" questions were cheap and
**should be settled before the fix, because they decide whether this is one
allocation site or a family.** Settled — and there is nothing left to fix.

| shape (100000 evaluations, bound is a verified variant) | allocations |
| --- | ---: |
| control, `i < 50000` against an int constant | 10 |
| `i < v` | 2 |
| `i <= v` | 2 |
| `i > v` | 10 |
| `i >= v` | 10 |
| `i == v` | 2 |
| `i != v` | 10 |

**Not a family and not one site: none of them allocate.** `==`/`!=` behave like
the ordered operators, and a constant bound behaves like a variable one. Results
were checked for correctness in the same run, not just counted.

### The probe error that nearly produced a false all-clear

**An unannotated parameter is not a reliable way to get a variant.** My first
four probes used one — including one called with both an int and a float — and
all showed 6-8 allocations, which I was one step away from reporting as "fixed"
while possibly never reaching the variant path at all. `PXXDBG=n.locals`
settles it: `mixed[0]` from a mixed list gives **tk=22**, a plain `5` gives
tk=13 and a plain `2.5` gives tk=19. The committed fixture takes its bound from
a mixed list for that reason and says so.

### Both controls, because a negative result needs them

- **Instrument:** the census reports **185,433** allocations on a deliberately
  allocating program, so it can count large numbers. Its reporting is on a
  geometric schedule (1..8, then ~1.2x), so the last line is the last SCHEDULED
  report — that is worth knowing before reading a small final number as a total.
- **Guard:** `assert_alloc_ceiling` at a ceiling of 100 against the fixture's
  own floor **fails** (`TOO MANY — allocs=727 exceeds 100`); at 3000 it passes.

### What is NOT established

**No source commit touched `PXXPromoVarCmpTry` or `PyVarCompare` since
2026-09-10** (searched over `compiler/*.inc`, `compiler/*.pas`,
`compiler/builtin/*.pas` — a plain `git log -S` over `compiler/` is
contaminated, because 41 MB of binaries briefly committed on 2026-09-22 contain
those symbols and match). So **the cause of the disappearance is unidentified,
and there is no old-binary control.** This closure is a claim about the
OBSERVABLE at HEAD, verified by route and by two controls, and it is not a
claim that someone fixed a thing I can name.

**That is why it closes behind a guard rather than on the measurement alone:**
if it was masked rather than repaired, the fixture reddens when the mask lifts.


## Log
- 2026-09-22 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 986d2d30d.
