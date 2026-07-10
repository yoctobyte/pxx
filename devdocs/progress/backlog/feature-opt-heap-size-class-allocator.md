---
prio: 52  # auto — real alloc-path win for alloc-heavy programs; independent of the register campaign
---

# Heap: segregated free lists (size classes) — kill the O(n) free-list walk

- **Type:** feature (runtime — allocator) — **Track O** (Optimization lane;
  file-ownership **Track A** — `compiler/builtin/builtinheap.pas` is core runtime
  the compiler itself links, so it carries A's self-host + cross gate).
- **Status:** backlog — filed 2026-07-10.
- **Opened:** 2026-07-10 (optimization campaign, heap-locality discussion).
- **Owner:** —

## Problem — one global first-fit free list

`PXXAlloc` (`builtinheap.pas`) today: bump pointer off a big mmap arena for fresh
memory (O(1), good), plus **one global free list** for reuse. On every alloc it
**walks that free list first-fit** (`while cur <> 0 … if PWord(cur-8)^ >= size`),
O(number of freed-but-unreused blocks). Two costs:

1. **O(n) walk per alloc** as the free list grows (free/realloc-churny workloads:
   sqlite, lua, string-heavy code).
2. **Size-mismatch reuse + no coalescing** — first-fit hands a 200-byte freed
   block to a 16-byte request (no split), and `PXXFree` just LIFO-pushes (never
   merges neighbours). Fragments over time.

It walks the *free list* (available chunks), NOT all heap — live memory and the
bump path are untouched. The free list is already "a list of available chunks";
the fix is to keep **several** lists, bucketed by size.

## Fix — segregated free lists (size classes)

Replace the single `FreeList` head with an **array of heads, one per size class**:

- Size classes: exact 8-byte multiples up to a cap (e.g. 8,16,24,…,512 → 64 bins),
  then a single "large" fallback list (or direct mmap) above the cap. Class index
  = `size div 8 - 1` below the cap.
- **Alloc**: go straight to `bin[classOf(size)]`, pop the head — **O(1)**, exact
  fit, no walk. Empty bin → bump from the arena (unchanged).
- **Free**: push onto `bin[classOf(header_size)]` — O(1). Header already stores
  the block's size, so the class is recoverable on free.
- Large/rare sizes: one fallback first-fit list (walk is now only over the rare
  big blocks), or mmap-per-block + munmap on free.

Effects: O(1) alloc/free on the common path, **exact-size reuse** (no
fragmentation from size mismatch), and same-size blocks cluster in memory →
**locality as a free side effect** (the "same page" goal, achieved structurally,
no profile needed — size is known at the call site).

## Keep invariants (correctness bar)
- Still round size up to 8, still 8-align payloads, still zero reused spans
  (callers assume fresh memory is zero — managed refcount/length headers,
  dynarray/instance slots).
- Still return distinct, non-overlapping blocks; header at `[p-8]` unchanged so
  `PXXFree`/`PXXRealloc` keep working.
- Per-target: `HEAP_ARENA` differs (ESP static 64 KiB arena vs 256 MiB mmap) —
  bin table must fit the static-arena build too (small fixed array, fine).
- Thread-safety: the existing `PXXHeapSpin` lock still wraps alloc/free; bins are
  just more state under the same lock.

## Not in scope
- **Type segregation** (int-pages vs ansistring-pages): marginal beyond
  size-classing (same type usually = same size already), and `PXXAlloc` only sees
  a `size`, not a kind — would need a type tag threaded through every alloc site
  (managed strings, dynarrays, instances). Defer; revisit only if measurement
  shows same-size-different-type contention.
- **Coalescing adjacent free blocks**: a further step (needs boundary tags);
  size-class bins already remove the dominant cost. Optional follow-up.

## Gate (file-ownership Track A — core runtime)
`builtinheap.pas` is linked into the compiler itself and every compiled program,
so: `make test` + self-host byte-identical (heap layout does not affect emitted
bytes, but a heap bug crashes the compiler — verify), alloc-heavy corpus still
green (sqlite `:memory:` + file-VFS, lua), and the 5 libc-free cross targets
(the static-arena path). Land only green.

## Acceptance
- Segregated bins land; alloc/free O(1) on the common path (no free-list walk
  below the large cap).
- Measured: free-list-walk instructions gone from an alloc-heavy profile;
  fragmentation (bytes handed out vs requested) does not regress.
- All gates green; self-host byte-identical.

## Links
[[feature-opt-o3-register-pressure]] (sibling optimization ticket, orthogonal —
that one is stack/codegen, this is heap/runtime) · umbrella
[[feature-optimization-levels]].
