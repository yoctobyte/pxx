---
track: A+O
prio: 40
type: feature
blocked-by: []
summary: "Split out of decide-interface-members-in-aggregates-lock-strategy, where a reentrant heap lock was proposed as a means to fix an ARC leak. That is not what it is for: EmitAcquireHeapLock's own comment says the allocator does not scale because the lock is global, and that per-thread arenas need TLS the runtime lacked. TLS landed 2026-08-20, so both are now open — judged as allocator work, not as a prerequisite for a bug fix."
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
