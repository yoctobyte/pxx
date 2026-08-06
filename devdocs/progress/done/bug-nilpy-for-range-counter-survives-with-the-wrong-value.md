---
track: N
prio: 55
type: bug
summary: "NilPy: after `for i in range(3)` the variable holds 3 (the value that FAILED the test), CPython says 2 — and after an EMPTY range it is clobbered to `start` instead of keeping its previous value"
status: done
owner: claude-A-N
---

# A range counter survives the loop with the wrong value

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-06, bughunting with `tools/pydiff.py`, alongside
  [[bug-nilpy-for-range-loop-counter-is-32-bit-and-never-terminates]]. Distinct
  from it and independent of the counter's width — this is the counter's
  terminal value, not its size — so it was split out rather than folded in.

## Measured (self-hosted binary at `08bea9451`; identical on `pinned`, so
pre-existing and not a regression of the width fix)

```python
for i in range(3):    pass
print(i)              # CPython 2    pxx 3
for j in range(5, 8): pass
print(j)              # CPython 7    pxx 8
for k in range(0, 10, 3): pass
print(k)              # CPython 9    pxx 12
```

pxx leaves the value that FAILED the test — `stop`, or the first step past it.
CPython leaves the last value actually yielded. With a step the gap widens (12
vs 9), so this is not a uniform off-by-one anyone could paper over.

The second facet is the more dangerous one, because it destroys data that was
already there:

```python
i = 99
for i in range(0):    pass
print(i)              # CPython 99   pxx 0
```

An empty range must leave the name alone (CPython binds the loop variable only
when the body runs). pxx initialises the counter unconditionally, so an
unentered loop silently overwrites an existing binding with `start`.

Nested loops show both at once: `for a in range(3): for b in range(2): …` leaves
CPython `a=2 b=1`, pxx `a=3 b=2`.

## Why it matters

"Use the loop variable after the loop" is ordinary Python — a search loop that
reports where it stopped, a counter read once the loop ends. Nothing raises;
the value is simply one step past, which reads as plausible.

## Cause

The counted-loop desugar makes the user's variable BE the loop counter: it is
initialised to `start` before the test and incremented before the test is
re-run, so on exit it necessarily holds an out-of-range value, and on zero
iterations it holds `start`. Both symptoms are that one choice.

## The fork whoever takes this has to settle — it is a PERF call

Correctness is not in question (CPython is the spec). The implementation is,
because `for i in range(n)` is the language's hottest construct:

1. **Hidden counter, copy into the user variable at the top of each body
   iteration.** Exactly CPython for both facets, including the empty-range case,
   and needs no special-casing of `break` (which must keep the current value —
   correct today and must stay so). Costs one store per iteration; whether the
   optimizer removes it in the common case is **unmeasured**, and measuring it is
   part of the ticket.
2. **Keep today's shape; subtract the step on normal exit.** Nearly free, and
   fixes the surviving-value facet. Does *not* fix the empty-range clobber
   without an additional entry guard, and needs care so a `break` path does not
   also subtract.

Recommend measuring 1 first (with `-O2`, the proven default) and falling back to
2 + a guard only if the per-iteration store actually shows up. Do not guess from
the shape of the emitted code — this repo's rule is to measure.

## Gate

Per-fix loop. A `.npy` test covering: post-loop value with and without an
explicit step, an empty range over a previously-bound name, a `break` (value at
the break point), nested loops, and a comprehension (whose hidden loop name must
NOT leak) — diffed against CPython with `tools/pydiff.py`. If option 1 lands,
also record a before/after timing of a hot `for i in range(N)` loop in the log.

## 2026-08-06 — FIXED with option 1, and the perf fork settled by MEASURING it

Option 1 as recommended: the loop runs on a hidden counter and the user's variable
is assigned from it at the **top** of each body iteration. Both facets fall out of
that one change — the last value assigned is the last one yielded, and an unentered
loop assigns nothing, so an existing binding survives. `break` keeps the value at
the break point, which was already correct and is why the copy is at the top of the
body rather than a correction after the loop.

**Both loop shapes needed it, and the second is the common one.** The stepped form
lowers to `i = start; while i </> stop: body; i += step`; the no-explicit-step form
lowers to a Pascal `AN_FOR` over `start..stop-1`. Fixing only the first left
`for i in range(3)` — the commonest spelling there is — still wrong, which the
first test run caught immediately (`i 0` instead of `i 2`).

Comprehensions keep the old shape and pay nothing: they already loop on
`PyCompHiddenLoopName`, so the hidden name IS the counter and nothing outside can
observe its terminal value. `userSym = -1` marks that case.

### The perf fork: measured, not guessed — and the cost is zero

The ticket asked whether the per-iteration store shows up. It does not.

The obvious A/B is misleading and worth recording: timing HEAD against `pinned`
suggested a 10-20% regression, but **pinned's answer is wrong** — it prints
1365447424 where the correct sum is 3999980000000, because it still has the 32-bit
counter of `bug-nilpy-for-range-loop-counter-is-32-bit-and-never-terminates`. It was
doing narrower arithmetic, not the same work faster.

The fair comparison is the same compiler with the copy on and off. Over a
200 x 200000 `for i in range(n)` accumulate at `-O2`, 8 runs each:

| build | min | mean |
| --- | --- | --- |
| copy DISABLED | 1.31s | 1.513s |
| copy enabled | **1.29s** | **1.491s** |

The copy-enabled build is marginally *faster* on both statistics, i.e. the
difference is entirely run-to-run noise (the spread within either build is ~0.35s).
So option 2 — subtract the step on exit, plus an entry guard — was not needed, and
the exactly-CPython lowering is also the free one.

### Test

`test/test_nilpy_range_counter_after_loop.npy`, 14 lines diffed clean against
CPython, covering everything the Gate section asked for plus a few shapes it did
not: no-step / explicit-start / explicit-step / DESCENDING step, two kinds of empty
range, nested loops, `break`, a single-iteration loop, a body that READS the
variable (so the copy must be the first statement), rebinding the variable inside
the body, a comprehension's name not leaking, a stepped comprehension, and a
computed (non-literal) bound. Swept the whole nilpy for/range/comprehension/
enumerate corpus: zero failures.

## Log
- 2026-08-06 — resolved, commit 58cc242da.
