# Parallel processing as a language feature

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Blocked-by:** feature-unified-heap-allocator
- **Opened:** 2026-06-06 (user request)

## Motivation

Expose parallelism as a first-class language surface, not just raw pthread
binding. Today there is low-level groundwork — `--threadsafe` /
`{$THREADSAFE ON}` emits atomic refcounts, and `test/test_multithreading.pas`
drives raw pthread workers — but no language constructs for spawning and joining
work, sharing data safely, or expressing data-parallel loops.

## Scope (design-open)

Pick a model and a minimal surface; this ticket is the design + first slice:

- **Threads / spawn-join.** A `TThread`-like class or a `spawn`/`sync` pair: start
  a routine on a worker, join/await its result.
- **Synchronization.** Surface mutex / atomic primitives (the `--threadsafe`
  path already emits atomics for refcounts — generalize to user locks).
- **Data-parallel loop** (stretch): a `parallel for` that fans iterations across
  a worker pool, with a clear rule on what's shareable.
- **Memory model.** State what's safe to share vs. copy. Ties to managed-value
  ownership: shared mutable managed values need atomic refcounts (have) plus a
  uniqueness/ownership story (copy-on-write uniqueness checks still need external
  sync today — see `feature-managed-string-default`).

Design context: `../../developer/threads-todo.md` (ordered thread arc),
`../../developer/threading-and-heap-design.md`. The worker-pool / resumable-frame
mechanism can be **shared with** `feature-async-coroutines` (one event loop +
pool, two surfaces) — design them together rather than twice.

## Why blocked

Concurrent allocation needs the **thread-safe shared heap** the allocator arc
delivers; the thread arc in `threads-todo.md` is explicitly ordered after the
unified allocator. Parallel code doing I/O also wants
`feature-threadsafe-io-serialization` (statement-atomic `write`/`writeln`) — not
a hard blocker, but expect to need it in the same breath.

## Acceptance

A program spawns workers, joins results, and shares data through the chosen
primitives with correct results under repeated runs (data-race-free for the
covered surface); self-host fixedpoint holds; `--threadsafe` covers the atomic
paths.

## Log
- 2026-06-06 — ticket opened from user request.
