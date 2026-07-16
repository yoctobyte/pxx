---
prio: 45  # auto
---

# Parallel processing as a language feature

- **Type:** feature
- **Status:** working
- **Owner:** A-parallel
- **Blocked-by:** feature-threadsafe-heap-contract
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

Concurrent allocation needs a proven **thread-safe heap contract** for the active
memory-management mode. The unified allocator has landed, and `--threadsafe`
covers important refcount paths, but Track A still needs to audit/define the
heap behavior for real preemptive threads; see
`feature-threadsafe-heap-contract`. Parallel code doing I/O also wants
`feature-threadsafe-io-serialization` (statement-atomic `write`/`writeln`) — not
a hard blocker, but expect to need it in the same breath.

## ESP32 / FreeRTOS (decided 2026-06-18)

Threads route through the OS/RTOS — **PXX will not ship a bare-metal scheduler**.
Rationale: anyone wanting threads on ESP is, in practice, already pulling in
ESP-IDF for Wi-Fi / BLE / drivers, so threads = **FreeRTOS tasks** (the IDF
profile). See
[developer/concurrency-memory-model.md](../../developer/concurrency-memory-model.md).

- **`threads ⇒ idf`.** A bare program (`--esp-profile=bare`) that uses the thread
  surface is a **hard error** pointing at `--esp-profile=idf`. Bare stays
  self-contained — FreeRTOS must never become a hidden dependency of the bare
  profile.
- **Binding, not syntax.** Expose FreeRTOS task create/join + **optional core
  pin** under the same spawn/join surface, not new keywords.
- **Dual-core SMP.** ESP32 is dual-core (PRO/APP). The "core 0 = networking,
  core 1 = app" split is an IDF pinning **convention, not hardware-enforced** —
  tasks pin to a core or float. Surface the pin as an option on spawn.
- **Memory model.** Each FreeRTOS task is a **statically-sized stack** (no MMU
  growth) — same discipline as a stackful coroutine, chosen at task creation.
- `--threadsafe` already emits atomic refcounts; reuse for the ESP path.

Distinct from the coroutine work: stackless/stackful coroutines are *cooperative*
and the RAM-cheap default for embedded (feature-async-auto-backend /
feature-stackful-coro-port). Threads are the *preemptive multicore* axis and only
make sense on the IDF profile.

## ESP target profile default (related)

Formalise `--esp-profile={idf,bare}` with **`idf` as the default** (≈99% of real
apps use something from IDF) and `bare` a first-class one-flag opt-in (tiny
images, no IDF toolchain, fast language testing under qemu). Tracked here because
the `threads ⇒ idf` rule needs the profile to be an explicit, queryable selector.
Today the IDF path is implied by `.o`/`--emit-obj` output and bare by
`--esp-profile=bare`; unify them under one flag.

## Acceptance

A program spawns workers, joins results, and shares data through the chosen
primitives with correct results under repeated runs (data-race-free for the
covered surface); self-host fixedpoint holds; `--threadsafe` covers the atomic
paths. On ESP: the thread surface compiles+runs under the IDF profile (FreeRTOS
tasks, optional core pin) and is a clear error under `--esp-profile=bare`.

## Log
- 2026-06-06 — ticket opened from user request.
- 2026-06-18 — ESP/FreeRTOS strategy + `threads ⇒ idf` + profile-default decision
  recorded (design discussion); see developer/concurrency-memory-model.md.
- 2026-06-28 — blocker moved from the completed unified allocator to
  `feature-threadsafe-heap-contract`: refcounting exists in threadsafe mode, but
  heap safety needs an explicit Track A contract per memory-management mode.

## Part of the multithreading epic (2026-06-30)

Umbrella: [[meta-multithreading]]. Invariant: threading is opt-in/off-by-default;
single-threaded self-build stays byte-identical; no libc (Linux syscalls only).
