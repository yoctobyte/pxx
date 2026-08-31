---
track: A+O
prio: 45
type: feature
blocked-by: []
summary: "PROMISE MEASURED 2026-09-01, and a PREREQUISITE nobody had named. Promise: 2M GetMem/FreeMem pairs, total fixed, split across N workers (flat = perfect scaling) goes 0.14s at 1 worker to 0.39s at 12 — 2.8x WORSE, i.e. adding threads makes fixed allocator work slower. A null with the identical loop and per-iteration call but no heap traffic is flat at <=0.01s at every worker count, so dispatch is under 3% and the degradation is entirely the global heap lock. Measured at f23f141f997d, AFTER the refcount path went lock-free (274a9da6c), so it is allocator contention and nothing else. PREREQUISITE: TLS is NOT reachable from where the arenas would live — every TLS_SLOT read is hand-emitted code in ir_codegen.inc, and builtinheap.pas (PXXAlloc, HeapPtr, HeapEnd) has no TLS reference of any spelling. A Pascal-reachable TLS accessor comes first. The reentrancy half stays parked by the owner 2026-08-21; do not re-litigate it."\n
status: backlog
owner: unassigned
---

# Reentrant heap lock, and the per-thread arenas it was really for

- **Track A**, tagged **O** (optimization — it lands under A's gate and A's
  file-ownership like every O ticket).
- Split out 2026-08-21 by the answer to
  [[decide-interface-members-in-aggregates-lock-strategy]], which took option
  (b) for the ARC family and freed this to be its own question.

## Why this is not a bug-fix prerequisite

The interface-in-aggregates family wanted a reentrant lock because record-field
finalization runs under the non-reentrant heap spinlock and
`PXXIntfRelease -> _Release -> Free -> FreeMem` re-acquires it and spins forever
(confirmed under `{$threadsafe on}`; an attempt at it, `cb2ed843`, was reverted
in `87108477` back to a benign leak).

That family is now served by moving the interface pass **outside** the lock —
the proven shape, already shipping for class fields. So reentrancy is no longer
load-bearing for any open bug, and this ticket exists to ask the allocator
question on its own terms.

## What the allocator actually needs, in its own words

`EmitAcquireHeapLock` (`compiler/ir_codegen.inc`) already replaced a bare
`lock xchg` loop with TTAS+PAUSE and measured it:

    threads      1     2     4     8
    xchg loop   66ms 100ms 132ms 171ms
    TTAS+pause  60ms  74ms  90ms 122ms
                      -26%  -32%  -29%

and its comment states the ceiling plainly:

> *"It does NOT make the allocator scale — the lock is still global and one
> thread allocates at a time; that needs per-thread arenas, which needs real
> TLS, which this runtime does not have yet."*

**That last clause is now stale.** `gs`-based TLS landed 2026-08-20
([[feature-a-thread-local-storage-via-clone-settls]],
[[feature-a-tls-block-for-the-main-thread]]) with a slot convention and free
slots reserved. Fix the comment as part of this work.

## The two pieces, in order of value

1. **Per-thread arenas** — the actual scaling fix, and the reason TLS was wanted.
   One thread allocating at a time is the ceiling every benchmark above hits.
2. **Reentrancy (owner + depth)** — now a smaller, optional convenience. It would
   let a release run anywhere rather than requiring the unlocked-pass discipline,
   and would delete a standing hazard class rather than routing around it.

They compose: per-thread arenas make the shared lock rare, which makes an
owner/depth check cheap in the case that remains.

## Costs, measured before committing

- **Confined to `--threadsafe`.** `EmitAcquireHeapLock` opens with
  `if ThreadSafeMode then` — a default build emits no heap lock at all, so
  nothing here touches the default build's allocator path. The old objection
  that reentrancy "changes the allocator's core locking for all code" was
  overstated and should not be carried forward.
- **Two implementations to keep in step.** x86-64 uses the hand-emitted
  TTAS+PAUSE blob in `ir_codegen.inc`; i386 uses a separate Pascal spinlock
  (`PXXHeapSpin`, under `PXX_TS_SOFTLOCK`) because it has no lock blobs. One
  concept, two mechanisms — a `normalise-dont-special-case` smell in its own
  right, and worth asking whether they should converge before either grows a
  depth counter.
- The uncontended acquire currently costs one `lock xchg`; an owner/depth check
  adds a TLS read, a compare and a branch to it. Measure, do not argue — the
  400k-pair benchmark above is the harness.

## Gate

`make compiler/pascal26` + self-host fixedpoint, `tools/gate.sh quick`, and —
because this is heap-critical and threading-shaped — the threading stress tests
via Track T's heavier tiers rather than the native quick tier alone. That
requirement is what the original decision named and it survives the split.

## User's position, 2026-08-21 — do not re-litigate the reentrancy half unprompted

Asked directly, after walking through why
[[decide-interface-members-in-aggregates-lock-strategy]] took (b):

> *"i'm good and if we ever encounter a real world project that has an issue, we
> will look at it again."*

So the **unlocked-pass discipline is accepted as the design**, not tolerated as a
stopgap. The standing objection to it — that every future release site must
remember to run outside the lock, where a reentrant lock would delete the hazard
class — is real, recorded, and deliberately not acted on.

**Unpark trigger: a real-world project hitting it.** A deadlock, or a new managed
member kind whose release cannot be hoisted out of the lock. Not "it would be
tidier".

This does NOT park the ticket. **Per-thread arenas stand on their own merit** —
the allocator serialises every thread through one lock, which is a measured
ceiling (see the TTAS table above), and that is a performance ticket, not a
correctness one. Reentrancy is the half the user set aside.


---

## 2026-09-01 (frankB) — promise measured, and the blocker is not the one on file

I did not implement this. I measured whether it is worth implementing, which is
what this ticket's own "Costs, measured before committing" section asks for, and
found a prerequisite that changes the shape of the job.

### Promise: yes, and it is the bad kind of curve

`allocscale.pas` — 2,000,000 GetMem/FreeMem pairs TOTAL, split across N workers
by `pwFixed`, each pair in its own frame so nothing is shared. Total work is
constant, so **a perfectly scaling allocator would be FLAT**. Compiler
`f23f141f997d`, 12 cores, load 0.54, min of 3:

| workers | alloc | null | vs 1 worker |
| ---: | ---: | ---: | ---: |
| 1 | 0.14s | 0.01s | 1.00x |
| 2 | 0.21s | 0.00s | 1.50x |
| 4 | 0.33s | 0.00s | 2.36x |
| 8 | 0.40s | 0.00s | 2.86x |
| 12 | 0.39s | 0.00s | 2.79x |

**Adding threads makes fixed allocator work 2.8x slower.** That is worse than
"does not scale" — it is negative scaling, and it is the ceiling the TTAS
measurement in `EmitAcquireHeapLock` predicted in words.

The null column is load-bearing and cost me one wrong version. My first null
replaced `GetMem`/`FreeMem` with `p := nil; if p <> nil then FreeMem(p)`, which
is dead code: the compiler removed the loop and I measured an empty program at
0.00s, which "confirmed" what I wanted. The null above keeps the identical loop
and an identical per-iteration CALL, and feeds a non-foldable result into the
reduction — `acc=1000000` proves 2M iterations ran. It is flat at <=0.01s at
every worker count, so parallel-for dispatch contributes under 3% of the 0.39s
and **the entire degradation is the heap lock**.

Measured AFTER `274a9da6c` made retain/release lock-free, so this is allocation
and freeing only. A pre-274a9da6c whole-program number would have conflated the
two.

### The prerequisite: TLS is not reachable from the allocator

This ticket says the TLS clause in `EmitAcquireHeapLock`'s comment "is now
stale" because TLS landed 2026-08-20. **Half right, and the surviving half is
the blocker.**

- TLS exists, with the slot convention in `compiler/defs.inc`
  (`TLS_SLOT_SELF`, `_TID`, `_STACK_LO`, `_STACK_HI`, `_SIG_*`) and free slots.
- **Every read of a slot is hand-emitted machine code in `ir_codegen.inc`.**
  `grep -rn 'TLS_SLOT' compiler/builtin/ lib/rtl/` returns nothing, and
  `builtinheap.pas` — which is where `PXXAlloc`, `HeapPtr` and `HeapEnd`
  actually live — contains no TLS reference of any spelling.

`PXXAlloc` is Pascal and cannot ask which thread it is on. So per-thread arenas
need **a Pascal-reachable TLS accessor first**. That is a prerequisite rather
than a detail, and it is the real answer to "why has nobody done this" — not
that nobody got to it.

The comment in `ir_codegen.inc` has been corrected to say this. I had first
written it as "the stated blocker is gone and the work is open on its merits",
which is what this ticket says and is wrong in the direction that would have
sent the next agent straight into `builtinheap.pas` looking for a TLS read that
is not there.

### What the job actually is, in order

1. A Pascal-reachable TLS accessor (or move the arena bookkeeping to where TLS
   already is). **Unmeasured** — I did not price this.
2. Per-thread bump regions: grab a chunk under the lock, bump lock-free, so the
   common path stops touching the global word.
3. Free-list interaction, including cross-thread frees, which is where the
   correctness risk is and which the 2.8x above says nothing about.

Step 1 is the one to price next. The promise number is now on file so nobody has
to re-derive it, and the harness is `allocscale.pas` + its null.

### Not taken further

I hold the managed-memory group and this is its umbrella's last open child, but
step 1 is a different piece of work in a different file than the one this ticket
names, and step 3 carries real correctness risk that wants its own session.
Banking the measurement rather than starting a three-step change I could not
finish. The reentrancy half remains parked by the owner's 2026-08-21 position —
unchanged and not re-litigated here.
