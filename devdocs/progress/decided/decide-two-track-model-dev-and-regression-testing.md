---
prio: 60
---

# DECIDED: two operational tracks — development, and regression testing

- **Type:** decide (user call — the model itself)
- **Track:** T records it; it governs the whole fleet
- **Status:** done
- **Owner:** — (user)
- **Decided:** 2026-07-31, verbally, at the xeon box

## The call

> "i stick to devving and regression testing as 2 tracks. A+ waters down, T is
> pretty correct. right now Xeon box is the right place for track T and will
> stop devving agents from over-gating. that's the whole goal. development is
> sortof linear and track A is not easily parallized but track T is."

Operationally there are **two** things, not a dozen:

1. **Development** — one broadly linear stream. Everything lowers to one IR,
   through one self-host gate, into one history.
2. **Regression testing (Track T)** — the matrix, continuously, on its own box.

## The axis this splits on: parallelism, not file ownership

This is the correction worth keeping. The letters were built to answer *"who
owns this file when two agents run at once"*. The split that actually holds is
**what parallelizes**:

| | development | Track T |
|---|---|---|
| shape | linear — one IR, one gate, one history | 1617 jobs × 6 targets, embarrassingly parallel |
| scales by | *not* easily parallelized | cores, straightforwardly |
| box | borg — faster per core, interactive | xeon — 12 threads, 60 GB |

`A+C`, `A+*` and friends **water it down**: they suggest dev is several
concurrent lanes when in practice it is one stream. The frontend letters stay
useful as *labels* — which gate must be green, what context to hold, who owns a
ticket — but they are not concurrency lanes and should not be dispatched as if
they were.

C/P/N/Z/R sharing Track A is **by design**, not a defect: frontends lower to a
shared IR, and lexer/parser work usually reaches the IR layer anyway, so it is
Track A. Track A is the single mutex; everything else works around it.

## The goal, stated plainly

**Stop dev agents over-gating.** Testing was eating ~80% of the dev loop. Track
T exists so development pushes on a fast local confirm and the breadth arrives
asynchronously — see `two-box-protocol.md`, "Do not RUN native on the dev box".
Track T is not a governance layer over development; it is the thing that lets
development stop waiting.

## Consequence — deprioritise the A-mutex work

`decide-ir-intake-shrink-track-a-mutex` was **not filed**, deliberately. Track T
had drafted a proposal to shrink Track A's critical section (generated IR
opcode numbering from a registry; landing an op on one backend; queueing for A).
It was premised on **five frontends contending for A**. Under a linear dev
model that contention is largely hypothetical, so the proposal does not earn its
cost. Recorded here so it is not rediscovered as a fresh idea:

- *generated IR numbering* — real (the 72 ops are dense, hand-assigned `0..71`
  in `defs.inc`, and the numbers are build-internal so renumbering is free), but
  it only pays when two agents append concurrently. Park it.
- *declared partial-target support* — **survives, and moves to Track T.** An IR
  op implemented on x86-64 but not riscv32 currently surfaces as a mystery red;
  declaring per-target support turns it into a known gap. That is tstate signal
  quality, not Track A design.

## What does not change

- Track A remains the single mutex, with the sole-A guard as written.
- The claim in `working/` remains the real lock, checked on origin.
- Write scopes are unchanged: tstate belongs to the watcher host, T's tooling to
  whoever holds T.

## For the peer box

`claude@borg`, `fable-a-n`: read dispatch as **dev vs T**, and do not expand
`A+*` into concurrent lanes. If a one-liner names several letters, treat them as
scope hints for a single linear stream, not as a fan-out.
