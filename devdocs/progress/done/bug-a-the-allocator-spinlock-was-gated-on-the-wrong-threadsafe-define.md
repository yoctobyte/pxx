---
slug: bug-a-the-allocator-spinlock-was-gated-on-the-wrong-threadsafe-define
title: the allocator spinlock was gated on the wrong threadsafe define, so x86-64 --threadsafe had no heap lock for helper allocations
summary: >
  On x86-64, `--threadsafe` selects PXX_TS_HARDLOCK, and the spinlock that
  guards the allocator state (FreeList/HeapPtr/HeapEnd) INSIDE
  PXXAlloc/PXXFree was gated on PXX_TS_SOFTLOCK -- so on the one target
  everything is built for, those nine sites compiled out. The hard lock does
  not cover the gap: it is emitted by the CODEGEN around the tkGetMem/tkFreeMem
  sites and PXXAlloc does not take it, so every allocation reached from a
  Pascal HELPER ran with no mutual exclusion. PXXObjAlloc is that route, and
  it is how every list, tuple and dict is born. Two threads got the same block.
  Re-gated on PXX_THREADSAFE; fixture test_nilpy_threaded_container_alloc.
track: A
type: bug
prio: 90
owner: frank-user
status: done
---

## The measurement

Two threads each building their own container per iteration, `--threadsafe`
against `--threadsafe -dPXX_TS_SOFTLOCK` on the same source, three runs each:

| kind | plain | with the spin forced on |
| --- | --- | --- |
| list | 217 217 139 | 0 0 0 |
| tuple | 139 217 139 | 0 0 0 |
| dict | 217 217 217 | 0 0 0 |
| int | 0 0 0 | 0 0 0 |
| str | 0 0 0 | 0 0 0 |

`rc=217` is `IndexError: list index out of range` on a list built three
elements long one statement earlier -- the other thread had the same block and
reset FLen. `rc=139` is the free list itself. Under `-dPXX_LIBC_HEAP` it aborts
inside glibc, which is what said the defect is a lost/duplicated block and not
our allocator's bookkeeping.

## Why int and str were clean, and why that is the whole diagnosis

A NilPy int is unboxed. A managed string is allocated by the CODEGEN's own
emitter, which holds the hard lock across the call. Only the helper route --
`PXXObjAlloc -> PXXAlloc`, a plain Pascal call the codegen never wraps -- was
exposed. That split is what named the mechanism, and it is also why every
fixture written from strings was green while the bug was live.

## What was ruled out first, cheaply

- **The heap magazine.** `-dPXX_NO_HEAP_MAG` still fails 5/5. The magazine
  bypasses PXXAlloc entirely and is thread-local; it is not on this path.
- **The object refcount.** Fixed on 2026-09-13 by another seat and verified
  here on the built binary: `objdump` counts exactly one `lock` prefix inside
  each of PXXObjRetain and PXXObjRelease. Atomic, and not the cause.
- **The dynarray refcount helpers.** Six sites were mis-gated the same way and
  are fixed in this commit, but `TPyList.FItems` is a raw GetMem block, not a
  refcounted dynamic array, so that path is not the container path. A real
  sibling defect that moved no reproducer.

## Deadlock, since the comment that put the gate here warned of one

None. The two locks nest one way only: a codegen'd tkGetMem site takes the hard
lock and then calls PXXAlloc, which takes the spin; nothing acquires the hard
lock while holding the spin, because the spin exists only inside
PXXAlloc/PXXFree and those never take the hard lock. The original objection --
"a lock taken inside PXXAlloc would be re-acquired by its own holder, and this
lock is not reentrant" -- is about the HARD lock being moved inside PXXAlloc,
which is not what this does, and it is stale besides: the hard lock has been
reentrant since feature-a-make-the-heap-lock-reentrant.

## Cost

One `xchg` per PXXAlloc/PXXFree in a `--threadsafe` x86-64 build. The magazine
fast path does not call PXXAlloc, so the hot path is unchanged. Nothing moves
in a default build -- PXX_THREADSAFE is undefined there and `compiler/pascal26`
came out byte-identical across the change.

## What it unblocked

lekkerzeilen. The demo's nondeterministic death (rc=139 / rc=217 / rc=135
across runs, including the owner's "bus error") is gone; it now fails the same
way every run, on `tile (x, y): object is not subscriptable`. The
`TypeError: unsupported operand type(s) for -: 'set' and 'tuple'` that
bug-a-something-in-lekkerzeilen-s-startup... records as "racing with the loader
thread" was this: a freed-and-reused container block read back with the wrong
FKind.

## Log

- 2026-09-14 frank-user: re-gated the nine allocator-spin sites on PXX_THREADSAFE, commit 02b7f7250; fixture test_nilpy_threaded_container_alloc wired in the same commit. gate quick GREEN.
