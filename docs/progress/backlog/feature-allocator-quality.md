# Allocator quality: split / coalesce / bins / alignment

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-06 (follow-up to feature-unified-heap-allocator)

## Motivation

The shared pure-Pascal allocator (`PXXAlloc`/`PXXFree`/`PXXRealloc`,
`lib/rtl/builtin.pas`) is delivered and self-hosts, but is deliberately simple:
first-fit free list, 8-byte size header, no splitting/coalescing, reused blocks
returned whole (over-allocate when a big freed block serves a small request),
and `Realloc` always copies on grow.

## Scope

- **Block splitting** — carve a smaller block from an oversized free block.
- **Coalescing** — merge adjacent free blocks to fight fragmentation.
- **In-place resize** — `Realloc` grows into a following free block when possible.
- **Size bins / segregated free lists** — O(1)-ish fit instead of first-fit scan.
- **Honor the `align` argument** (currently always 8).

Do this only after measuring real fragmentation/throughput on the compiler's own
allocation pattern; the simple version is correct and may be good enough.

## Acceptance

Fragmentation/throughput improves on a measured workload with no correctness
regression; `make bootstrap` byte-identical + `make test` + `make test-nilpy`
stay green.

## Log
- 2026-06-06 — ticket opened as the quality follow-up to the allocator redirect.
