---
prio: 30
track: B
---

# Demo — parallel hashing / mini proof-of-work

- **Type:** feature — example app. Track B/E (build with `$(PXX_STABLE)`; a
  compiler/frontend gap it hits → file under the owning lane).
- **Opened:** 2026-07-17 (parallel-demo candidate).
- **Relation:** integer/compute companion to `examples/parallel/collatz.pas` and
  `membw.pas`. Uses `parallel(P) for` + `reduction`
  ([[feature-parallel-for-scheduling-policy]]). Can reuse the crypto in
  `lib/**` (sha256 already exists — see the lib-test roster).

## Goal
A relatable, compute-bound integer demo: **mini proof-of-work**. Over nonces
`[0..N-1]`, hash `(prefix || nonce)` and count / find those whose digest has ≥ K
leading zero bits.
```pascal
var found, bestZeros: Integer;
found := 0; bestZeros := 0;
parallel(pdChunked) for nonce := 0 to N-1
  reduction(+: found)
  reduction(max: bestZeros)
do begin
  z := LeadingZeroBits(Hash(prefix, nonce));   { Hash = function, private scratch }
  if z >= K then found := found + 1;
  if z > bestZeros then bestZeros := z;
end;
```
- **Compute-bound** (hashing is ALU-heavy, little memory traffic) → scales close
  to linear, the clean counterpoint to `membw`'s memory wall.
- **Deterministic** for a fixed prefix/N → serial == parallel exact (count +
  best-zeros), a real correctness oracle.
- **Relatable** ("mining") and shows two reduction ops (`+` and `max`) in one pass.
- `Hash` is a function so its state is private per worker (safe pattern).

## Hash choice
- Simplest: a small integer mixing hash (splitmix64 / xorshift / FNV) — no
  dependencies, plenty of ALU, fully in registers. Best for the pure-compute story.
- Realistic: SHA-256 from `lib/**` (already in the lib-test roster) — heavier,
  "real crypto", but pulls the lib in. Offer both via a `--hash fast|sha256` flag.

## Extensions
- **Throughput report** — hashes/sec serial vs parallel (the headline number for a
  "miner").
- **Actually find a nonce** — stop-early once a target difficulty is hit (needs a
  shared found-flag; note that early-exit across workers is a separate concern —
  the current parallel-for has no cancellation, so v1 scans the whole range and
  reduces, no early stop).

## Constraints
- Build with `$(PXX_STABLE)`; never rebuild the compiler.
- No automated multithread test without explicit permission (core-pegging) —
  manual-validation, compile-smoke at most. A single-threaded fixed-seed digest
  check is fine to automate and bounded.

## Acceptance
- A PoW demo: for a fixed prefix + N + K, prints found-count, best-leading-zeros,
  and hashes/sec (serial vs parallel); asserts parallel == serial. Compiles +
  runs x86-64; compiles cross. `--hash fast` default; `--hash sha256` optional.

## Log
- 2026-07-17 — Filed as a parallel-demo candidate (compute-bound counterpoint to
  the memory-bound membw demo; fast integer hash default, sha256 optional; two
  reductions +/max; note the no-cancellation limitation for early-exit).
- 2026-07-20 — resolved, commit HEAD.
