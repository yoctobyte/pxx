---
status: done
---

---
slug: bug-a-a-nilpy-object-allocation-takes-no-heap-lock-on-x86-64-threadsafe
title: "a NilPy object allocation takes NO heap lock on x86-64 --threadsafe, so two threads get the same block"
track: A
type: bug
prio: 80
status: open
owner: unassigned
created: 2026-09-13
found-by: frankH (Track N, from the lekkerzeilen demo)
blocked-by: []
summary: >
  Two threads that each allocate their OWN private list segfault 5/5 on x86-64
  --threadsafe. PXXObjAlloc/PXXObjAllocRaw/PXXObjAllocRaw2 call PXXAlloc as an
  ordinary Pascal call, and on x86-64 the heap lock is emitted by the CODEGEN
  around tkGetMem/tkFreeMem sites only -- PXXAlloc itself does not take it. So
  every NilPy container construction allocates unlocked and two threads are
  handed the SAME BLOCK (objtrace: two `A` records on one address with no `F`
  between them). Under PXX_TS_SOFTLOCK (i386/aarch64/arm32) PXXAlloc DOES take
  PXXHeapSpin itself, so this is x86-64 only -- the default target, the one the
  demos and the whole dev loop run on. NOT a shared-container contract question:
  the two lists are private and never meet. The reentrancy objection that kept
  the lock out of PXXAlloc is ALREADY GONE (feature-a-make-the-heap-lock-reentrant
  landed 2026-09-06); ir_codegen.inc still cites it as parked.

## Repro — 22 lines, no sqlite, no queue, no shared container

```python
import threading
import time

DONE = 0


def worker():
    global DONE
    i = 0
    while i < 300000:
        _x = [1, 2, 3]          # the worker's OWN list, discarded
        i = i + 1
    DONE = 1


t = threading.Thread(target=worker, daemon=True, name="w")
t.start()
until = time.monotonic() + 20.0
while DONE == 0 and time.monotonic() < until:
    _y = [4, 5, 6]              # the main thread's OWN list, discarded
print("ok")
```

`pascal26 --threadsafe r.npy r && ./r` -- **5/5 segfaults**, at
`ee5b6adc7`..`a893dfc58` and under `stable_linux_amd64/default/stable_pinned`.

## The measured table — what breaks is the ALLOCATED KIND, five runs per row

Both threads allocate the same kind per iteration, nothing shared but a
module-level int:

| both threads allocate | segfaults |
| --- | --- |
| list `[1, 2, 3]` | **5/5** |
| dict `{"a": 1}` | **5/5** |
| tuple `(1.0, 2.0, 3.0)` | **5/5** |
| string `"x" + str(1)` | 0/5 |
| user-class instance `C(i)` | 0/5 |

And the discriminating negatives, which is what rules out every other suspect:

| probe | segfaults |
| --- | --- |
| a SHARED dict read by both, written by one, **no allocation** | **0/5** |
| worker allocating, main thread only `time.sleep` | **0/5** |
| worker allocating, main thread `t.join()` | **0/5** |
| worker doing pure ARITHMETIC, main allocating | **0/5** |
| the same allocate/discard loop, SINGLE-THREADED, 600k iterations | **0/10** |
| **Pascal**: two `palthreadobj.TThread`s growing dynamic arrays of strings | **0/5** |
| **Pascal**: two threads doing raw `GetMem`/`FreeMem(128)`, 300k each | **0/5** |

The two Pascal rows are the ones that matter: the threadsafe HEAP is fine, and
`GetMem` is fine **because `GetMem` is a token the codegen wraps** (and on
x86-64 routes through the TLS magazine). A Pascal *call* to `PXXAlloc` is not a
`tkGetMem` site and gets neither.

## Where it is

`compiler/builtin/builtinheap.pas`, `PXXObjAlloc` (and `PXXObjAllocRaw`,
`PXXObjAllocRaw2`), each of them:

```pascal
base := Int64(PXXAlloc(size + PXX_HDR_SIZE, 8));
```

`ir_codegen.inc` states the protocol in its own words:

> *"On x86-64 the heap lock is emitted by the compiler AROUND the call
> (EmitAcquireHeapLock at the tkGetMem and tkFreeMem sites); PXXAlloc does not
> take it."*

...and `PXXAlloc`'s `{$ifdef PXX_TS_SOFTLOCK}` arm takes `PXXHeapSpin` on the
other three targets. So the protocol has a hole for exactly one kind of caller
-- Pascal runtime code -- on exactly the default target.

## The evidence that it is the ALLOCATOR and not the refcount

`-dPXX_OBJTRACE -dPXX_HEAP_DEBUG`, one address's whole history:

```
A 1   R 2   r 1   r 0   F 0       first life: allocated, retained, released, freed
A 1   R 2                          second life: allocated, retained
A 1                                *** a THIRD `A` on the same address, rc reset to 1,
                                       with NO `F` since the second ***
r 0   F 0   R 1                    freed by one thread; retained by the other after
```

Two allocations of one address with no free between them is the allocator
handing the same block to both threads. The debug heap independently reports
`pxx-heap: RELEASE of a FREED object` on **8 of 10** threaded runs and **0 of
10** single-threaded ones.

The crash itself lands in `PyListGrow`'s copy loop reading `l.FItems` as nil
with `FLen > 0` (`mov (%rax),%rax`, rax=0, si_addr=0) -- a list object whose
fields belong to the other thread's list.

## Three candidate routes, and the blocker on the obvious one is gone

1. **Generalise `HeapLockedCallProcIdx1`** -- the existing mechanism that wraps
   ONE named runtime proc's CALL SITES in acquire/release (it names
   `PXXClassFinalizeManaged` and nothing else today, resolved at the call site
   by `Procs[procIdx].Name`). Make it a small set and add the three object
   allocators. Design-consistent, no new primitive.
2. **Make `PXXAlloc`/`PXXFree` self-locking on x86-64 too**, i.e. drop the
   SOFTLOCK-only guard. `ir_codegen.inc` says this *"DEADLOCKS"* and needs
   *"the reentrancy half that the owner parked on 2026-08-21"* -- **that is a
   stale hazard block.** The reentrancy landed 2026-09-06
   (`feature-a-make-the-heap-lock-reentrant`: BSS_HEAP_OWNER/BSS_HEAP_DEPTH on
   top of BSS_HEAP_LOCK). Re-measure before quoting the deadlock. The known
   cost is the +7%/+14% that ticket measured.
3. Give the object allocators their own Pascal-visible lock -- **wrong**, and
   recorded so nobody tries it: it must be the SAME word `tkGetMem` takes or the
   two families do not exclude each other.

## Not the shared-container ticket

`feature-nilpy-threadsafe-containers` (prio 45) is about concurrent mutation of
a SHARED list/dict, and its body asserts *"--threadsafe makes the runtime safe
-- allocator spinlock, atomic refcounts"*. On x86-64 both halves of that
sentence are false, which is this ticket. A note has been added there.

## Found beside a second, independent defect — already fixed

`PXXObjRetain`/`PXXObjRelease` guarded their atomic refcount arm on
`PXX_TS_SOFTLOCK`, so on x86-64 object refcounts were a plain non-atomic
read-modify-write (objdump: 142 lock prefixes in the binary, ZERO in those two
routines). Fixed by keying the arm on `PXX_THREADSAFE`. **It does not fix this
ticket** and was measured not to: the heap-debug report rate is 29 vs 27 over 20
runs either way, because the allocation race dominates. Recorded so the next
reader does not mistake one for the other.

## CLOSED BY EVENTS 2026-09-14, verified 2026-09-16 (frankS, Track A)

**Fixed two days after this was filed, by the owner's own `02b7f7250`
("fix(A): the allocator spinlock was gated on the wrong threadsafe define"),
and nobody closed the ticket.** Picked up at the top of the queue at p90; the
diagnosis here was correct and the work was already done.

`02b7f7250` names this exact mechanism in its own body -- *"the hard lock does
not cover the gap: it is emitted by the CODEGEN around the tkGetMem/tkFreeMem
sites and PXXAlloc does not take it -- so an allocation reached from a Pascal
HELPER (PXXObjAlloc -> PXXAlloc, which is how every TPyList/TPyDict/tuple is
born) held nothing."* The spinlock guarding FreeList/HeapPtr/HeapEnd inside
PXXAlloc/PXXFree was gated `PXX_TS_SOFTLOCK`; x86-64 `--threadsafe` selects
`PXX_TS_HARDLOCK`, so those nine sites compiled out on the one target
everything is built for. The gate is now `PXX_THREADSAFE`. `bc3ab775e`
(2026-09-13, object refcounts not atomic on x86-64 --threadsafe) is the
sibling mis-gating one layer up.

**`PXXObjAlloc` STILL DOES NOT TAKE THE LOCK ITSELF and that is no longer the
defect** -- the mutual exclusion moved INSIDE `PXXAlloc`, which is the better
place for it, so reading this ticket's "Where it is" section against today's
source will show the quoted code unchanged and invite a re-fix. It is correct
as it stands.

Re-measured at `7addc40f08af`, this ticket's own repro verbatim, 10 runs per
row against the 5/5 recorded above:

| both threads allocate | segfaults then | segfaults now |
| --- | --- | --- |
| list `[1, 2, 3]` | 5/5 | **0/10** |
| dict `{"a": 1}` | 5/5 | **0/10** |
| tuple `(1.0, 2.0, 3.0)` | 5/5 | **0/10** |

Two independent sources agree and they fail differently: the owner's own
measured table in `02b7f7250` (list/tuple/dict racing, int/str clean -- the
same split this ticket found) and this re-run.

NOT attributed to any work of mine in this session: the current pin v410
(`06e40fb95b13`, 2026-09-14 18:44) already postdates both fixes, which is why
the "repros under stable_pinned" line above no longer holds either.

## Log
- 2026-09-16 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 5d43fa076.
