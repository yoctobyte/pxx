---
summary: "pasmith divergence signatures are too coarse: end-of-program divergences all collapse to pxx-vs-fpc_trace-length, so distinct bugs can over-dedup and hide each other"
type: feature
prio: 35
track: T
---

# pasmith: finer divergence signatures (end-of-program over-dedup)

- **Type:** feature (fuzzer tooling — Track T owns the tool).
- **Status:** backlog
- **Opened:** 2026-07-15, noticed while landing the interface rung
  ([[feature-pasmith-deep-oop]]).
- **Related:** [[feature-pasmith-pascal-program-generator]] (the ledger / signature
  design), [[bug-a-interface-release-on-last-ref-not-destroyed]] (the finding that
  exposed this).

## Problem

The ledger dedups findings by `signature(cls, kind) = "<class>_<kind>"`, where `kind`
comes from the trace checkpoint at which two oracles first disagree
(`checkpoint_kinds`). That works well when the divergence sits ON a traced statement —
the kind names the construct (`intfcall`, `case`, `strassign`, ...) and 500 instances
of one bug collapse to one ledger entry.

But a divergence that only manifests **after the last checkpoint** — at the final
`writeln(cs)`, once destructors / finalization / end-of-scope cleanup have run — has
no per-statement checkpoint to localize to. It falls to the catch-all signature
**`pxx-vs-fpc_trace-length`** (observed: the interface release bug — the destructor
folds happen at end-of-program, every body checkpoint agrees, only the final fold
differs).

Consequence: **every end-of-program divergence, regardless of cause, gets the same
signature.** If two *distinct* end-of-program bugs exist (say the interface release
bug and a future dynarray-finalization bug), the second is silently marked "known"
and never surfaces — the exact over-dedup the ledger is supposed to prevent, just
displaced from "too many tickets" to "too few."

## Sketch of a fix (T's call at pickup)

- Emit an **end-of-program checkpoint sequence**, not just one final number: `Snap`
  after each destructor / finalization step, tagged with a kind
  (`dtor:TIfc`, `final:dynarray`, ...). The existing trace-diff localizer then names
  the guilty release the same way it already names a guilty statement, and the
  signature carries the construct instead of the generic `trace-length`.
- Alternatively, fold a per-object / per-type marker into each destructor (the class
  and interface rungs already fold a class index) and let `checkpoint_kinds` read it,
  so the signature is `dtor_TIfc` vs `dtor_TC3` rather than a shared bucket.
- Keep it cheap: this is signature granularity only, not new oracles.

## Acceptance

Two deliberately-different end-of-program divergences (e.g. an interface-release and a
managed-record-finalization repro) produce **two distinct ledger signatures**, not
one; the interface bug's signature names the interface/destructor construct rather
than `trace-length`.
