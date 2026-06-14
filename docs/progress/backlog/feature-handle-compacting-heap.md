# Handle-table compacting heap (anti-fragmentation for constrained RAM)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-14 (design discussion: ESP32 heap fragmentation)

## Motivation

ESP32 (and any small flat-address target) has tight RAM and no MMU/paging, so a
long-running app that churns managed strings / dynamic arrays / objects
fragments the heap and eventually fails to allocate even with free bytes
available. We want the full managed runtime (strings, dynarrays, objects) usable
on ESP32 without that wall — ideally **compaction** that an app can run on
intervals / when idle.

A naive precise *moving* GC (scan every typed variable, slide objects, fix all
pointers) is the wrong first move: the heap walk is easy (layout RTTI exists,
`feature-rtti-layout-table` done), but precise **stack + register root finding**
at an arbitrary pause needs safepoints + stack maps (a large compiler feature),
interior-pointer handling, and is dangerous under interrupts/RTOS (an ISR or
other task holding a raw pointer across a compaction = silent corruption). Avoid.

## Design: three allocation lanes, each matched to its access pattern

The key insight: **what a reference *is* decides whether you can move the
object.** User code that holds a *handle* can have its target moved; user code
that holds a *raw address* cannot (without stack maps).

1. **Managed strings + dynamic arrays → handle-table compaction (moving).**
   These are already handle-based: user code holds a handle (pointer to the heap
   block), derefs through it. Route them through a **handle table** where each
   slot holds `{addr, size}` and the handle points at the *slot* (stable).
   Compaction walks the handle table + free list, slides live blocks down, and
   rewrites only `addr` in each slot — **stack and globals are never touched**
   because they point at stable handles. This is the old Mac OS `Handle` /
   Smalltalk object-table trick: no stack maps, no safepoints, no register
   scanning. **Lock** a handle while a raw data pointer to its block is live
   (char-index write, syscall/DMA buffer) so it can't move mid-use; unlock after.
   PXX is ~80% there because the managed types already use handles.

2. **Objects → size-class / per-class pools (non-moving).** An object reference
   is a *raw* instance pointer held everywhere (`Self`, fields, registers, vmt
   dispatch), so it is NOT cheaply compactable. But the worrying workload —
   frequent create/free — is the *easy* case for free-lists: instance size is
   known at compile time, so allocate from a per-size (or per-class) free list
   and Free returns the slot. Same-type churn recycles the same slots, O(1), zero
   fragmentation. This belongs in **`feature-allocator-quality`** (size-class
   bins) and almost certainly solves the object case without any moving.

3. **Raw `Pointer` / `@x` → plain non-moving region (pinned).** Uncollectable by
   construction; lives in the ordinary allocator. Correct and safe.

## Escalation (only if measured)

If real-world *varied-size, long-lived survivor* fragmentation (not churn —
churn is handled by lane 2) proves the pools insufficient for objects:
- **Object table (Smalltalk-style handles for objects):** make an object
  reference a handle into an object table; compaction rewrites the table. Lets
  objects compact too. Cost: every field access and method dispatch becomes
  double-indirect (handle → table → instance → vmt), `Self`/casts/`is`/`as` go
  through the table — a **pervasive OOP-codegen ABI change** and a hot-path perf
  hit. Defer until measurement demands it; record here, don't lead with it.

## Drawbacks / risks (acknowledged)

- Handle deref = one extra indirection per access (lanes 1, and 2 only if escalated).
- Lock/unlock discipline around every raw-pointer window (string char write,
  buffers handed to syscalls/DMA) — get this wrong and compaction corrupts a
  live buffer. Needs an audited list of raw-pointer-exposing paths.
- Pinning: DMA / interrupt-touched buffers must be pinned (never moved).
- Programmer accepts the constrained-RAM model — this is opt-in (a profile),
  not the default desktop allocator.

## Scope (when picked up)

- Handle-table allocator variant for strings/dynarrays: handle = table slot;
  compaction pass `PXXHeapCompact` walking table + free list; lock/unlock API.
- Retarget the managed-string/dynarray runtime (`builtinheap`) deref + the
  emitted index/length/COW paths to go through the table on this profile.
- Audit + lock all raw-data-pointer windows (char-index write, `PXXSysRead`/
  write buffers, `@s[i]`, DMA).
- A profile switch (ties to `feature-static-arena-profile` /
  `feature-no-ansistring-profile` family — these are allocator *profiles*).
- Leave objects on lane 2 (pools, in `feature-allocator-quality`).

## Acceptance

- A churn+survivor workload that exhausts the simple first-fit allocator runs
  indefinitely under the handle-compacting profile on the i386/QEMU oracle and
  on ESP32.
- `make bootstrap` byte-identical, `make test`/`test-nilpy` green, cross suites green.

## Priority / sequencing

**Low — after the core ESP32 work** (`feature-esp32-bare-boot`,
`feature-esp32-idf-xtensa`, riscv32 done). Do **`feature-allocator-quality`
(bins + coalescing) FIRST and measure** — it is non-moving, near-zero risk, and
on ESP32 likely removes enough fragmentation that this ticket may not be needed
at all. This ticket is the targeted compaction step only if measurement still
shows a wall.

## Relation

- Builds on the existing handle-based managed-string/dynarray model and
  [[project_rtti_streaming_plan]] / layout RTTI (done).
- Pairs with `feature-allocator-quality` (object pools = lane 2) and
  `feature-unified-heap-allocator` (done — the shared allocator this profiles).

## Log

- 2026-06-14 — opened from the ESP32 heap-fragmentation design thread. Settled:
  three-lane architecture (handle compaction for strings/dynarrays, size-class
  pools for objects, pinned region for raw pointers); precise moving GC rejected
  (stack maps / RTOS danger); object table recorded as measured-only escalation.
  Gated behind allocator-quality + ESP32 core work.
