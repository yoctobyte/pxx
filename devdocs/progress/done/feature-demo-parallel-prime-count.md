---
prio: 30
track: B
---

# Demo — parallel prime count / find

- **Type:** feature — example app. Track B/E (build with `$(PXX_STABLE)`; a
  compiler/frontend gap it hits → file under the owning lane).
- **Opened:** 2026-07-17 (parallel-demo candidate).
- **Relation:** integer companion to `examples/parallel/collatz.pas` (uneven load)
  and `membw.pas` (memory-bound). Uses `parallel(P) for` + `reduction`
  ([[feature-parallel-for-scheduling-policy]]). There is already a serial
  `examples/primes/sieve.pas` to reuse / contrast.

## Goal
The cleanest EVEN-LOAD integer showcase: count primes in `[2..N]`.
```pascal
var primes: Int64;
primes := 0;
parallel(pdChunked) for n := 2 to N reduction(+: primes) do
  if IsPrime(n) then primes := primes + 1;
```
`IsPrime` is a function (trial division up to sqrt(n)) → its scratch is private on
the worker stack, result folds into the reduction var (the safe pattern). Pure
integer, deterministic (serial == parallel), embarrassingly parallel.

Contrast with Collatz: prime trial-division cost grows smoothly with n (roughly
sqrt(n)), so contiguous `pdChunked` is already fairly balanced — a good foil to
Collatz where the cost is erratic. Optionally also time `pdOnDemand` to show it's
~equal here (distribution matters only for erratic loads).

## Phases / extensions
1. **Count** (above) — serial vs parallel timing + reduction agreement.
2. **Segmented sieve** — a memory + integer variant: sieve `[lo..hi]` blocks in
   parallel (each worker owns a disjoint segment, sieves with the base primes),
   count set bits. Closer to how real prime enumeration scales; touches the
   memory side too.
3. **Find the largest prime gap** in the range via `reduction(max: gap)` — shows
   a second reduction op on the same pass.

## Constraints
- Build with `$(PXX_STABLE)`; never rebuild the compiler.
- No automated multithread test without explicit permission (core-pegging) —
  manual-validation, compile-smoke at most. A single-threaded correctness check
  (count matches a known π(N)) is fine to automate and bounded.

## Acceptance
- A prime-count demo: serial vs parallel timing, `reduction(+)` total, asserts
  parallel == serial and matches the known prime count for the chosen N (e.g.
  π(10^7) = 620,458). Compiles + runs on x86-64; compiles cross.

## Log
- 2026-07-17 — Filed as a parallel-demo candidate (even-load integer foil to
  Collatz; segmented-sieve extension for the memory angle).
- 2026-07-20 — resolved, commit HEAD.
