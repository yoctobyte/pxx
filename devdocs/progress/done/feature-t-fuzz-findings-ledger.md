---
summary: "Fuzz findings ledger: dedupe by signature, throttle fuzzing until the finding is fixed"
type: feature
prio: 70
resolved: 49728c23
---

# Fuzz findings ledger — one entry per cause, and a tap that closes and reopens itself

- **Type:** feature (Track T — the tooling).
- **Status:** **done** — landed 2026-07-14 (`49728c23`, refined in `db01a921`).
- **Owner:** trackt
- **Opened / closed:** 2026-07-14. Filed retroactively: the work came directly from a
  user request in-session, not from the queue.
- **Related:** [[feature-pasmith-pascal-program-generator]] (the tool),
  [[feature-pasmith-widen-grammar]] (landed alongside — a wider grammar makes the
  dedupe *more* necessary, not less), [[feature-fuzzer-idle-scheduling]] (the idle
  trigger this rate-limits).

## The problem, as the user put it

> "The other day we had hundreds of duplicated fuzzing reports (all the same underlying
> issue). So we sort of need to rate-limit that. As soon as a fuzzer found an issue, we
> file it and from there on rate-limit fuzzing, allowing other tracks to catch up and fix
> it. However, as soon as it's fixed, we can continue fuzzing at will."

Concretely: **639 report files** in `tstate/fuzz/`, every one of them the same
`case`-selector defect (b346), re-found forever because the fuzzer was running the stale
*pinned* binary while Track A had already fixed it at HEAD. A fuzzer that reports one bug
639 times is not finding bugs; it is finding *a* bug, loudly — and the pile buries the
only number that matters, **distinct causes per CPU-hour**.

## What landed

**Signatures.** A finding is keyed by `<disagreement-class>_<statement-kind>` —
`pxx-vs-fpc_case`, `pxx-self_virtcall`, `pxx-reject_copy-dynamic-array-copy`. The class
comes from the oracle grouping; the kind comes from the trace checkpoint, since pasmith
now stamps `kind=` on every statement it traces. For a *rejected* program the kind is a
slug of the compiler's own diagnostic.

Coarse **on purpose**. A finer key (the statement's operators, a hash of its text) splits
one bug straight back into hundreds of "distinct" signatures, because the surrounding
expression differs every seed — the failure mode we are removing, dressed up as
precision. The cost (two simultaneous bugs in one construct read as one) is paid down by
keeping up to five example seeds per entry, and by the entry reopening the moment the
first is fixed.

**The ledger** — `devdocs/progress/tstate/fuzz/LEDGER.json`, one entry per signature,
with hit count, example seeds (each with its full gen-args), owning ticket and status.
The 639 files folded into one entry with `hits: 639`; the raw pile lives in git history.

**The rate limit**, exactly as asked:

- a **known** signature is counted, never re-filed;
- a **new** signature stops the slice on the spot (`--stop-on-new`) — file it, hand it to
  the owning lane, don't spend the remaining minutes re-finding it;
- while anything is unfixed, slices are spaced `fuzz_backoff_minutes` apart (default 90)
  instead of running every idle tick;
- every idle tick **rechecks** the unfixed entries against the current sha and marks the
  ones that stopped reproducing as `fixed` — so full-speed fuzzing resumes **by itself,
  on the fix**, not when a human remembers to re-enable it. Throttling on an open finding
  is only honest if something notices the fix without being asked.

**Statuses.** `open` (untriaged) and `ticketed` (filed, unfixed, generator can still emit
the shape) throttle. `fixed` does not. `dodged` does not either — filed, unfixed, but the
generator avoids the shape by construction (a `NO_*` constant in `pasmith.py`). The
distinction that matters is not "fixed or not", it is **can the fuzzer still trip over
it**: once the generator refuses to emit a shape it cannot re-derive that bug, so slowing
down buys nothing and costs every other bug we would have found meanwhile.

## One finding it produced immediately

The driver used to **filter a pxx compile failure out of the oracle groups**: the
survivors then all agreed and the program scored *clean*. A compiler that could not build
valid objfpc was invisible to every fuzz slice ever run. Scoring it as a finding surfaced
[[compat-pascal-copy-of-char-literal]] on the first run.

## Verification

Ledger/dedupe/stop-on-new/recheck exercised end-to-end against a stubbed oracle: 37
instances of one synthetic bug → **1 entry**; marking it fixed → tap reopens. `testmgr
--tier quick` GREEN. Docs: `devdocs/progress/tstate/fuzz/README.md`.

## Follow-ups (not blocking)

- The **borg watcher daemon must be restarted** to pick up the new `twatch.py` — a
  running daemon reloads config, not code.
- [[feature-pasmith-deep-oop]], [[feature-pasmith-multi-unit-programs]] — the remaining
  coverage gaps.
