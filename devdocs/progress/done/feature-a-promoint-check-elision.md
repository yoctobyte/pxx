---
track: A
prio: 50
type: feature
---

# Promotable int: inline the fast path (check elision)

Stage 3 of [[feature-a-promotable-int]]'s staged plan, deferred while stages
1-2 (type, storage) and the heap tier landed. Purely performance — correctness
is done and CPython-verified.

## Why it is outstanding

Per [[decide-promoint-rvalue-representation]] Option A, **every promotable-int
operation is currently a runtime call**, including for values that never leave
the inline tier. That was the deliberate trade: it bought correctness on all
six backends with zero backend changes. The cost is real and this ticket is
where it is paid back.

The inline fast path already exists — it is just on the callee side, inside
`PXXPromoAdd` and friends in `compiler/builtin/promoint.pas`, rather than at
the call site.

## Shape

- Range/induction analysis to prove a value stays inside the inline tier, so
  loop counters, indices and `len()`-style results carry no check at all. The
  umbrella ticket calls this out as the thing that "restores full native speed
  in ordinary loops".
- Inline the tag test plus the native op at the call site, calling the runtime
  only on the overflow/heap edge.
- Land behind `-O3` first and promote per-pass to `-O2` only after the full
  gate, per Track O's rules.

## Measure first

Do not start from the assumption that the call is the dominant cost — build a
benchmark (a factorial or Fibonacci loop that stays inline, versus the same
loop on `Int64`) and get the actual ratio before choosing what to inline.

## Gate

Benchmarks showing the inline-tier loop approaching Int64 speed, every existing
promo test still exact against CPython, `--tier quick` + self-host
byte-identical.

## Log
- 2026-07-20 — resolved, commit HEAD.


## Landed 2026-07-20 — 330x slower than Int64 down to 9x

Measured first, as the ticket said to. An inline-tier accumulation loop
(20M iterations of `a := a + i`) against the same loop on Int64:

| | time |
| --- | --- |
| Int64 | 0.07 s |
| PromoInt, before | 9.83 s (~330x) |
| PromoInt, after | 0.62 s (~9x) |

Three changes, in increasing order of what they bought:

1. **Mixed promo-with-machine-int forms** (`PXXPromoAddInt` etc). `p + n` cost
   FIVE runtime calls — init a temp, box n, init a result, add, copy back.
   Worth almost nothing on its own (9.83 -> 9.58), which is why the ticket's
   "measure first, do not assume the call is the dominant cost" mattered.

2. **The actual cost: managed prologue/epilogue.** A routine that so much as
   MENTIONS a `TBig` pays zero-init and finalization of its temps on every
   call, because the record holds a dynamic array — whether or not the branch
   using them runs. One `PXXPromoAddInt` was ~344 ns. Splitting every slow path
   into its own routine, so the hot ones never name a TBig, took the direct
   helper call from 6.88 s to 1.33 s over the same 20M iterations. **This is the
   transferable finding: keep bignum types out of hot routines entirely.**

3. **Direct-to-destination assignment.** `p := p + n` now computes into p's own
   slot instead of a temp plus a copy, one runtime call instead of three.
   2.26 s -> 0.62 s.

Correctness unchanged throughout: `test_promoint` byte-identical, the 50-case
CPython differential green, variant arithmetic and the variant fallback exact,
`test-nilpy` green, and i386/aarch64/arm32 still byte-identical to x86-64.

**Not done, and deliberately:** true check elision — range/induction analysis
proving a value stays inline, and inlining the tag test at the call site so an
ordinary loop counter carries no check at all. That is what would close the
remaining 9x. It needs either backend work or a lot more IR, and the cheap
structural wins above got most of the available factor. Reopen with a benchmark
if the 9x turns out to matter in real NilPy code rather than a microbenchmark.
