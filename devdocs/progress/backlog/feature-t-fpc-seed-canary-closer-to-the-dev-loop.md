---
summary: "The FPC seed build breaks every couple of days, always the same way, and only the watcher ever notices — yet it costs 10.7s. Put it where the person who broke it will see it."
type: feature
track: T
prio: 55
---

# The FPC seed canary is 11 seconds and lives where nobody looks

- **Type:** feature (Track T — tier composition)
- **Opened:** 2026-08-02 by `claude@xeon`, filing the second FPC-seed drift in
  two days.

## The pattern

| date | ticket | cause |
|---|---|---|
| 2026-08-01 | [[bug-a-fpc-seed-drift-pymaketruthy-forward-wrong-file]] | forward in the wrong file |
| 2026-08-02 | [[bug-n-fpc-seed-drift-pybytesci-used-before-forward]] | no forward at all |
| 2026-08-02 | [[bug-n-fpc-seed-drift-pywiden-needs-a-forward-in-parser-inc]] | forward missing in the FIRST-included file |

All three were introduced by a Track N feature commit, all are one-line fixes,
and all were found by the watcher hours later — after the author's context was
gone and after other work had stacked on top.

## Why it keeps happening, structurally

The seed build is the only thing enforcing "the compiler's sources stay
FPC-compilable". pxx's own frontend is more permissive than FPC (it resolves a
call to a function defined later in the same include; FPC is single-pass and
will not), so **the property is invisible to every check a dev actually runs**.
It is advisory, so it gates nothing. It runs only on the watcher box. A dev
loop deliberately optimised down to ~15 s will never see it.

That is not carelessness to be trained out — it is a signal placed where the
person who can act on it never looks.

## The measurement that makes this cheap

```
136110 lines compiled, 10.7 sec
```

The whole seed build. For comparison the quick tier is 2-14 s, so this is
not a rounding error — but it is not a suite either, and it is O(1) in the
size of the change.

**Instance #3 landed within hours of #2 being fixed**, which settles the
question of whether this is a run of bad luck: it is a standing property of the
layout that nothing in the dev loop can see.

## Options

1. **Add it to `quick`.** Simplest, and roughly doubles the inner loop
   (~14 s -> ~25 s). Probably too much: quick's whole value is that nobody
   thinks twice about running it.
2. **A `seed` tier / `gate.sh seed`** that a frontend change runs when it has
   touched `compiler/**`. Cheap and targeted, but opt-in — the same reason the
   current canary is missed.
3. **Make the watcher's fast tier report it FIRST.** It already runs on every
   push (~100 s on xeon); if the seed build is the first job and its red
   publishes immediately (the machinery from
   [[feature-t-publish-selfhost-red-immediately]] exists), the author hears
   within ~2 minutes rather than at the next full cycle. Keeps the inner loop
   untouched.
4. **Cheap static lint** for "called above its definition with no forward" in
   the `.inc` files. No FPC needed, runs in milliseconds — but it reimplements
   a compiler's scope rules badly, and the FPC build is the real oracle.

Recommendation: **3**, possibly with **2** for anyone who wants the check
locally. It costs the dev loop nothing, which is the constraint that matters
(`meta-t-dev-throughput-and-track-a-t-integration`: the point of the offload is
that dev does not wait).

## Not in scope

Making the canary a GATE. It is advisory on purpose — nothing day-to-day
depends on the FPC seed, and a hard gate on a path nobody uses would be the
worst of both worlds. The ask here is latency and visibility, not enforcement.

## Log
- 2026-08-03 — **instance #4 landed** ([[bug-a-fpc-seed-drift-emitasmx64-forward]]),
  this time in Track A's own files, which kills the reading that it was a
  Track N habit. Four in three days.
- **Partly done in `bed641cf8`**: option 2 (a local check), implemented in the
  shape option 1 wanted but could not afford — the canary runs CONCURRENTLY
  inside `gate.sh quick`, so wall time is max() not sum(). Measured beside a
  running full matrix (load 15.4): the 11s seed build cost ~3s of gate wall.
  Armed only when `compiler/` has uncommitted changes; a missing FPC is a SKIP,
  never a failure.
- **Still open: option 3**, the watcher-side half — run the seed canary FIRST
  in the fast tier and publish its red immediately. `gate.sh` only helps an
  agent that RUNS the gate; the model in
  [[meta-t-dev-throughput-and-track-a-t-integration]] is explicitly that dev
  pushes on a quick confirm and lets T report back, so the watcher path still
  needs to be the fast one. Keeping this ticket open for that.
- Option 4 (a static lint) stays rejected: FPC is the real oracle and now
  costs ~3s of wall time, so a bespoke scope-rule reimplementation would be
  strictly worse.

- 2026-08-08 — **option 3, front-of-queue half done in `2f8b551e7`**; the ticket
  stays OPEN for the rest. The canary now shares the self-host job's front-group
  slot in `Manager.__init__`'s sort, minus the abort (it stays ADVISORY).

  **Measured, and smaller than the ticket assumed:** the canary was already
  **#15 of 1187** in the native tier — the sort is longest-first and at 10.7s it
  sorts high — so it moves to #1, and with `hard_cap = nproc*2` the first ~24
  jobs start concurrently anyway. On an unconstrained box this is close to a
  no-op. It earns its place on a CONSTRAINED one (`--serial`, or a watcher with
  `max_cores`), where queue position is real wall time.

  **Still open, and it is the substantive half:** publishing the canary's red
  mid-run, so the author hears at ~11s rather than at the fast tier's end.
  twatch publishes at end-of-run; the existing early-publish machinery
  ([[feature-t-publish-selfhost-red-immediately]]) works by **aborting** the
  run, which is unavailable here by design — the canary must never gate. That
  needs genuine mid-run publish machinery in the publish path, which is
  safety-critical (cf. the false-RED family). Left open rather than bodged.

  Worth re-checking before building it: the canary has been in `native` since
  `eb63555d9` (2026-07-12), so a red already reaches the author at the fast
  tier's end (~2 min), not "at the next full cycle". The gap this ticket closes
  is ~11s vs ~2 min — real, but smaller than the framing suggests, and worth
  confirming against an actual drift before spending the publish-path work.
