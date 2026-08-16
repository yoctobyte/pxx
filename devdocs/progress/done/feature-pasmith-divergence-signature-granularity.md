---
summary: "pasmith divergence signatures are too coarse: end-of-program divergences all collapse to pxx-vs-fpc_trace-length, so distinct bugs can over-dedup and hide each other"
type: feature
prio: 35
track: T
---

# pasmith: finer divergence signatures (end-of-program over-dedup)

- **Type:** feature (fuzzer tooling — Track T owns the tool).
- **Status:** done
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

## 2026-08-16 — DONE, via the ticket's option 1 (an end-of-program checkpoint sequence)

The teardown was already a sequence of distinct phases; it just had no
checkpoints in it. `teardown_ckpt()` now emits one `Snap` per phase, in trace
mode only:

| kind | phase |
| --- | --- |
| `exitfold` | the scalar/string/set fold, before anything is released |
| `final:records` | the heap chain's Dispose loop |
| `dtor:classes` | `o<i>.Free` |
| `release:intfs` | `iw<k> := nil` — the refcount drop that runs the destructor |
| `dtor:hier` | hierarchy objects |
| `dtor:mptrs` | method-pointer objects |
| `dtor:props` | property objects |
| `dtor:clsm` | class-method objects |

`localize()` and `checkpoint_kinds()` needed **no change** — they already read
`{ checkpoint N kind=K }` and sign the finding with the kind at the first
differing checkpoint. The gap was that the teardown emitted no such markers, so
every end-of-program divergence fell past the last one into `trace-length`.

### Per PHASE, not per object — deliberately

`dtor:classes` covers all N objects rather than `dtor:o0`, `dtor:o1`, ...  That
is the same "coarse ON PURPOSE" call the ledger's own design note makes, and
here it has a sharper edge: **object count varies with the seed**, so a
per-object kind would make the signature seed-dependent and split one bug back
into hundreds of "distinct" entries — precisely the failure the ledger exists to
remove, dressed up as precision. A phase name is stable across every seed that
has that phase at all.

### Acceptance, demonstrated

Two deliberately-different end-of-program divergences in the same program, the
ticket's exact criterion:

```
bug A (class destructors)   -> pxx-vs-fpc_dtor:classes
bug B (property-obj dtors)  -> pxx-vs-fpc_dtor:props
DISTINCT signatures: True      neither is the catch-all: True
```

The interface case this ticket was opened for now signs as
`pxx-vs-fpc_release:intfs`, naming the construct instead of `trace-length`.

### What `trace-length` still means, and it is now honest

The last teardown checkpoint precedes `writeln(cs)` and folds `cs`, so a
teardown divergence lands on a NAMED checkpoint rather than falling through.
What remains in `trace-length` is a genuine difference in the NUMBER of
checkpoints — a structural divergence, which is a different thing and worth its
own bucket.

### Verified

- **The oracle is untouched**: non-trace output is **byte-identical** across 5
  seeds under `--wide` (checked against the pre-change generator). Only trace
  mode gained lines, and trace mode is used solely by `localize()`.
- Traced program compiles under BOTH pxx and FPC and their traces agree.
- All 8 kinds emit; `Snap` is safe after a `Free` because it folds globals,
  records, strings, enums and sets and never dereferences a class instance or a
  disposed node — while reading `cs`, which is the point: destructors fold into
  `cs` on their way out.
- `pasmith_run.py --check 40 --wide`: 40 seeds, 0 rejected by FPC.
- `pasmith_run.py --seeds 90010-90025 --wide`: 16 programs, 0 divergences.

## Log
- 2026-08-16 — resolved, commit PENDING-COMMIT.
