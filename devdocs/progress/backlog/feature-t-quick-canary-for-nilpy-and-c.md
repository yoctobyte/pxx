---
summary: "The 2-14s quick canary covers Pascal only; a NilPy change and a C change can both go out with no fast check at all. Add one dense .npy and one dense .c canary."
type: feature
track: T
prio: 70
---

# A quick canary for NilPy and C, matching the Pascal one

- **Type:** feature (Track T) — **Track T**
- **Opened:** 2026-08-01. Part of [[meta-t-dev-throughput-and-track-a-t-integration]].

## What exists

`testmgr --tier quick` maps to the single `test-quick` Makefile target: ~12
dense torture tests, each a compile + run + one-line compare, e.g.

```make
./$(COMPILER) test/test_dynarray_torture.pas /tmp/smoke_dyntorture26
test "$$(/tmp/smoke_dyntorture26 | tail -1)" = "total ok 27 / 27"
```

Measured **2–14s** total. That is exactly the right shape for an inner-loop
canary: a few programs that each exercise a lot and collapse to a short line.

## The gap

It is **Pascal-only**. A Track N or Track C change — which is most of the
current work, since NilPy is pulling in the bulk of it — has *no* fast check
between "it built" and the 554s suite. So the new dev loop (build + repro +
push) has no cheap way to notice that a NilPy fix broke unrelated NilPy, or that
a shared-parser change broke C.

## Asked for

One dense `.npy` and one dense `.c` in the same style, added to `test-quick`:

- Broad rather than deep: containers, str methods, classes/dunders, exceptions,
  int promotion, comprehensions, closures — the layers that actually break.
- **Self-summarising**: end with a short line like `total ok 41 / 41` rather
  than a long expected-output blob. Keeps the Makefile assertion one line and
  the failure readable.
- **Per-section lines before the summary**, so a failure localises. A single
  opaque checksum tells you *something* broke and nothing more — that is the
  known weakness of composite tests and it is cheap to avoid.
- Budget: ~1–2s each. If it grows past that it belongs in the full tier.
- For the NilPy one, the expectation should be **CPython's own output**, per the
  house rule for `.npy` tests.

## Deliberately not

Not a replacement for `test-nilpy` / the C suites — this is a canary, not
coverage. Coverage is Track T's matrix. The canary's only job is to catch gross
breakage in the 12s dev loop.

## Landmine

`test-quick` runs in the raw-make fixed-`/tmp` namespace, so it is subject to
[[feature-t-per-invocation-tmp-namespace-for-make-recipes]] — pick output paths
that do not collide with the existing `smoke_*` names.

## Gate

`testmgr --tier quick` stays under ~20s, and each new canary is confirmed to FAIL
against a deliberately reverted fix in its own language (not just to pass today).
