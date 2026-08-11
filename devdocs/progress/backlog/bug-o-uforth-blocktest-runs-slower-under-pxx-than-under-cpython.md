---
summary: "uforth's blocktest word set takes 413s compiled by pxx against CPython's 196s interpreting the same source — the AOT compiler is 2.1x SLOWER than the interpreter it is differentially tested against, and it is now the pole of two test tiers"
type: bug
track: O
prio: 45
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
