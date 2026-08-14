---
summary: "uforth's blocktest word set takes 413s compiled by pxx against CPython's 196s interpreting the same source — the AOT compiler is 2.1x SLOWER than the interpreter it is differentially tested against, and it is now the pole of two test tiers"
type: bug
track: O
prio: 65
---

# pxx-compiled uforth is 2.1x slower than CPython on `blocktest`

- **Type:** bug (Track O — optimization; file-owned by Track A per O's rule)
- **Found:** 2026-08-11 by Track T while sharding `test-uforth`
  ([[feature-t-shard-the-uforth-ans-suite-per-word-set]]). **Filed, not fixed:
  T owns the tool, never the bug.**

## Measured

Per-phase timing of `make test-uforth`, compiler at `96b4b40ab`, 12-core
plexus. Each word set is run twice — once by the pxx-compiled `uforth`, once by
CPython running `uforth.py` — because the test is a differential. That makes it
an accidental but rather direct **compiler-vs-interpreter benchmark on the same
program**:

| word set | pxx (compiled) | CPython (interpreted) | ratio |
| --- | --- | --- | --- |
| `blocktest.fth` | **413.3s** | **196.0s** | **2.1x slower** |
| `core.fr` | 8.1s | 2.5s | 3.2x slower |
| `coreexttest.fth` | 6.0s | 1.9s | 3.2x slower |
| `coreplustest.fth` | 4.8s | 1.5s | 3.2x slower |
| `stringtest.fth` | 4.2s | 1.1s | 3.8x slower |
| `memorytest.fth` | 3.7s | 1.3s | 2.8x slower |
| 4 uforth corpora | 12.0s | 3.7s | 3.2x slower |

The box was contended (the watcher held a tier), so **absolute numbers run
high** — but both runtimes were contended equally in the same loop, so the
RATIO is the trustworthy part, and it is consistent at ~2-4x across every
single subject. The Makefile's own long-standing note records the uncontended
pair as ~240s vs ~80s: **3x**, same story.

## Why this is worth a ticket rather than a shrug

Nil-Python is a **compiled** frontend. Losing to CPython — a bytecode
interpreter — by 2-4x on every subject measured is the opposite of the expected
result, and it is uniform, so it is unlikely to be one pathological word.

It is also no longer only a quality question. After the sharding above,
`test-uforth#blocktest` is **the single longest job in both the `limited` and
`full` tiers**, so it sets Track T's wall time on its own:

```
limited: 14 shards, pole = test-uforth#blocktest (~268s uncontended)
full:    same pole
```

Every other uforth shard is ~28-36s, most of that the repeated `uforth.py`
compile. So this one ratio is what stands between T and a ~30s uforth
contribution — halving it is worth roughly two minutes off every deep run the
watcher makes, all day.

## Where the cause probably is NOT

Not the x86-64 instruction selection, most likely: the workload the Makefile
describes is "a memory-walk and hash workload", i.e. it leans on the NilPy
object model — dict/list indexing, integer boxing, refcount traffic — rather
than on arithmetic in registers. A uniform 2-4x across unrelated word sets
points the same way: a per-operation constant in the runtime, not a bad loop.

**That is a hypothesis from the shape of the numbers, not a diagnosis.** Do not
act on it — `devdocs/dev/root-cause-over-microfix.md` and the debugging
playbook both apply, and this repo's history is explicit that every wrong root
cause here was a plausible story nobody diffed against an oracle.

## Suggested first step

Profile the compiled `uforth` on `blocktest` (`-g -O2` + `perf`, or the
allocator counters) and find where the time goes before changing anything. The
oracle is free and already wired: the same program, same input, under CPython.

`tools/bench_timing_devtest.py` and the uforth speed harness in
[[feature-t-uforth-benchmark-harness]] are the existing instruments.

## Routing note

Filed under **O** because it is a codegen/runtime speed question and O is the
visible lane for those. If the cause turns out to be NilPy lowering rather than
the shared runtime or backend, this belongs to **Track N** — reroute rather
than split it. Whoever picks it up should decide that from a profile, not from
this ticket's guess.

## Gate

A profile naming the dominant cost, and — if a fix lands — the ratio measured
again the same way (same loop, same box, both runtimes contended equally), plus
`make test-uforth` still byte-identical to CPython on all 13 word sets.

## 2026-08-13 — re-measured, raised to prio 65, and worked around

Measured on plexus from the watcher's own log, full tier, wall 821.1s:

| job | wall | share |
|---|---|---|
| **test-uforth#blocktest** | **594.8s** | **72%** |
| selfhost-fixedpoint#00 | 131.8s | 16% |
| test-core#1139 | 108.2s | 13% |
| 2326 others | in parallel behind them | — |

This ticket's "it sets Track T's wall time on its own" was, if anything,
understated: with the matrix at 2331 jobs and a 12-core box, one job is
three-quarters of the sweep, and everything else fits in its shadow.

It also explains a second symptom that had been read as a tiering problem. The
`limited` tier cost 686s against `full`'s 821s — 84% of the price for 78% of
the jobs — which made the three-rung escalation ladder nearly pointless. The
mechanism was this job: **both tiers carried the same pole**, so neither could
be faster than it. The middle rung was collapsed today
(`perf(T): collapse the watcher's middle rung`), and that collapse is only
correct while this remains true.

### Worked around, on purpose, with an expiry condition

`test-uforth#blocktest` is now demoted out of the per-sha tiers into a new
disjoint `slow` tier (`testmgr.SLOW_SHARDS`), which the watcher runs as an idle
rung after the full matrix (`idle_slow`). The corpus is still swept; it is no
longer swept on every sha. Full sweeps drop 821s -> ~440s.

**This weakens the urgency argument above and should not be read as weakening
the ticket.** Two things stay true:

1. The quality finding is untouched and is the real point — a *compiled*
   frontend losing to a bytecode interpreter by 2-4x, uniformly across every
   subject measured, is the opposite of the expected result.
2. The workaround has a defined end: `SLOW_SHARDS` exists to be deleted. When
   this lands and blocktest is ordinary again, put it back in `limited`/`full`
   where the densest NilPy regression corpus belongs, and re-check whether the
   middle rung is worth restoring.

Raised 45 -> 65 by the user, on seeing the 72% number.

Nothing about the diagnosis changed: the "where the cause probably is NOT"
section above is still a hypothesis from the shape of the numbers, and the
suggested first step is still to profile before touching anything.

## 2026-08-14 (claude-A-N, Track N) — a WHOLE-SUITE number, not just blocktest

While closing [[feature-nilpy-corpus-uforth]], the full ANS Forth / Forth 2012
suite (`tests/runtests.fth`: prelimtest, the tester harness, `core.fr` and
eleven word-set files) was run under both engines from an identical tree:

| engine | wall | result |
| --- | --- | --- |
| CPython 3.12 | **54.66 s** | 252 lines, 0 errors |
| pxx-compiled uforth | **153.18 s** | 252 lines, 0 errors, stdout byte-identical |

**2.80x slower**, on a real mixed workload rather than one test. So this ticket's
finding is not a blocktest peculiarity — blocktest is where it was first noticed,
and the ratio holds across the whole conformance suite.

The correctness half is settled and should not be re-litigated while optimising:
the compiled binary produces CPython's exact output, so any change here has a
byte-exact oracle to hold itself against. Re-run with
`cd <tree>/tests && ../uforth_pxx runtests.fth < /dev/null`.

**Provenance:** compiler at f2f56c876, self-hosted fixedpoint build, not rebuilt
during the runs; same tree, same input, stdin closed for both (the suite blocks
on an interactive ACCEPT otherwise, which will look like a hang).
