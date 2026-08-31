---
track: A+O
prio: 45
type: feature
blocked-by: []
summary: "PROMISE MEASURED 2026-09-01, and the blocker is SCOPE, not a missing primitive. Promise: 2M GetMem/FreeMem pairs, total fixed, split across N workers (flat = perfect scaling) goes 0.14s at 1 worker to 0.39s at 12 — 2.8x WORSE, i.e. adding threads makes fixed allocator work slower. A null with the identical loop and per-iteration call but no heap traffic is flat at <=0.01s at every worker count, so dispatch is under 3% and the degradation is entirely the global heap lock. Measured at f23f141f997d, AFTER the refcount path went lock-free (274a9da6c), so it is allocator contention and nothing else. WRONG MECHANISM IN THE TITLE, measured 2026-09-01: PXX_ALLOC_CENSUS on the very benchmark above reports bump=3 arenas=1 against ~2,000,000 reuse, so the workload is ~100% size-class BIN traffic and per-thread ARENAS would move 3 allocations out of 2M. The promise attaches to a per-thread BIN MAGAZINE. Ruled out cache-line true-sharing on FreeBins by giving each worker its own size class: it degrades the same (0.17->0.57s at 12), so the lock is the mechanism. Confirmed at source: the lock is emitted by the COMPILER around the call (ir_codegen.inc:8948 tkGetMem, :9059 tkFreeMem), not taken inside PXXAlloc. DESIGN: put the lock-free fast path in the EMITTER at those two sites, never inside PXXAlloc -- PXXAlloc is called by managed string/dynarray sites that already hold the lock, so an internal lock would need the REENTRANCY the owner parked; the emitter route keeps reentrancy parked and unneeded. NO ACCESSOR PREREQUISITE — an earlier version of this summary claimed one and was wrong. `__pxxTlsBase` (pasparser_expr.inc, AN_TLSBASE, IR_TLSBASE) is Pascal-reachable today, verified compiling and running inside parallel workers, and four TLS slots are free (TLS_SLOT_FIRST_FREE=12 of 16) where an arena needs two. THE REAL CONSTRAINT IS THE TARGET SET: `__pxxTlsBase` is x86-64-only while --threadsafe covers x86-64/i386/aarch64/arm32, so per-thread arenas built on it are an x86-64-only optimisation and the other three stay on the global lock. ONE ALLOCATOR (settled 2026-09-01): builtinheap.pas is the only one, its three PXXAlloc bodies are mutually exclusive PROFILES, and the native one already carries a {$ifdef PXX_TS_SOFTLOCK} arm — so arenas are a second capability arm in an existing function, an ordinary Track A change with NO fork and no decide-* needed. Scope to agree before starting, not a blocker. The reentrancy half stays parked by the owner 2026-08-21; do not re-litigate it."
status: working
owner: frankB
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

### CORRECTED 2026-09-01: there is no accessor prerequisite

**An earlier revision of this ticket (and of `EmitAcquireHeapLock`'s comment, commit
`10bbc6f3b`) claimed per-thread arenas need "a Pascal-reachable TLS accessor
first". That is false and this section is the retraction.**

`__pxxTlsBase` is a compiler intrinsic and has been since 2026-08-20:

    compiler/pasparser_expr.inc:4112   if CaseEqual(name, '__pxxTlsBase') then
    compiler/defs.inc:758              AN_TLSBASE = 96
    compiler/defs.inc:971              IR_TLSBASE = 73

Parser arm, AST node, IR op. Verified empirically, not read: a Pascal program at
`-O2 --threadsafe` calls it, gets a base, and gets a *distinct, correct* one from
inside `parallel for` workers.

**Why the original grep missed it, which is the reusable part.**
`grep -rn TLS_SLOT compiler/builtin/ lib/rtl/` returns nothing, and every clause I
built on that is still true: `builtinheap.pas` really has no TLS reference, and
`HeapPtr`/`HeapEnd` really are process-wide `Int64` globals. But `TLS_SLOT` is the
name of the slot *constant*; the accessor has a different name. **The grep was
correct and it was correct about the wrong name** — it proved "nothing uses TLS
here", and I read it as "TLS is not reachable from here". Those are different
statements and only the first was measured. Same family as everything in
*The name is not the thing*: it did not error, it answered.

**Slot budget.** `TLS_BLOCK_SIZE` = 128 bytes = 16 slots; 0..11 are taken
(`SELF, TID, STACK_LO, STACK_HI, SIG_CODE, SIG_ADDR, SIG_CTX, SIG_NUM, EXC_TOP,
EXC_OBJ, EXC_CLS, EXC_ADDR`) and `TLS_SLOT_FIRST_FREE = 12`. Four free; a bump
region needs two (ptr, end). It fits.

### The real constraint: target set, not primitive

`__pxxTlsBase` refuses on everything but x86-64, and the Error says why:

> the other targets have a readable thread register (aarch64 `tpidr_el0`, arm32
> `tpidruro`) but this runtime has no way to SET one yet

`--threadsafe` accepts **x86-64, i386, aarch64 and arm32**. So arenas built on
`__pxxTlsBase` are an **x86-64-only** optimisation, and the other three threaded
targets keep the global lock and the 2.8x negative scaling measured above.

That is the decision to take before starting — an x86-64-only allocator win is a
live option against a measured 2.8x regression, not a blocked one — and it is a
scope question, not a missing-primitive question.

### Residual settled: why the Error cites a ticket in `done/`

The Error names `feature-a-thread-local-storage-via-clone-settls`, which is in
`done/`. **The citation is precise, not stale**, and the resolution is that the
ticket is named after a mechanism it did not use:

- TLS landed via **`arch_prctl(ARCH_SET_GS)`**, emitted in the clone stub
  (`compiler/thread_emit.inc:86-88`), which acts on the *calling* thread — so it
  needed no clone flag, no sixth `__pxxclone` argument and no per-arch IR_CLONE
  change. `PXX_CLONE_THREAD` is therefore **still `$350F00`** and still omits
  `CLONE_SETTLS`; that decode is correct and is no longer the blocker it was
  when the ticket was filed.
- The ticket's own closing section records what it did **not** do: i386,
  aarch64 and arm32 have a readable thread register and no way to set one
  (i386 wants a `struct user_desc`). The Error cites the ticket for exactly that
  residue.

**One stale line in it, worth knowing before you read it.** Its tail says
*"threading is x86-64-only today anyway (the clone stub exists on four arches but
`--threadsafe` gates the rest)"*. That is the same false claim swept from five
source sites by
[[bug-a-threadsafe-is-x86-64-only-is-asserted-in-five-places-and-has-been-false-since-july]]
(resolved `4eb58366c`) — `--threadsafe` has accepted four arches since
`07fee0844`, 2026-07-06. **That sweep covered `compiler/**` comments and two
`devdocs/dev/` docs; it never looked in `devdocs/progress/done/`**, so the claim
survives in the one document the compile-time Error points every reader at. Left
in place as a session record with a dated note appended there rather than
rewritten.

### MEASURED 2026-09-01: this ticket names the WRONG MECHANISM

**Per-thread ARENAS would not move the benchmark that establishes this ticket's
promise. Not by a little — by three allocations out of two million.** Anyone who
implements what the title says will deliver nothing and the numbers above will
be unchanged. This section is the correction; the slug stays because it is cited.

**The census, not an argument.** `-dPXX_ALLOC_CENSUS` on the exact `allocscale`
benchmark whose 2.8x is quoted in the summary:

    allocs=1955451  reuse=1955448  list=0  bump=3  arenas=1
    sizes 32:2 64:1955449

**`bump=3`, `arenas=1`, reuse ~100%.** The workload is a `GetMem`/`FreeMem` pair
in a loop, so after the first iteration every allocation is a size-class bin pop
and every free is a bin push. `HeapPtr`/`HeapEnd` — the state per-thread arenas
would privatise — are touched three times in the whole run. **The promise is
attached to the bins, not the arenas.**

### Which contention: the lock, not the bin data — separated by experiment

With ~100% bin traffic, "the degradation is entirely the global heap lock" (this
summary's own claim) had a live competitor: **true sharing of `FreeBins[7]`**,
one hot cache line ping-ponging between workers. Both predict the same 2.8x, so
the claim was asserted rather than shown.

Separated with `binsplit.pas` — same benchmark, but `pdChunked` gives worker *w*
a contiguous `i` range, so `size := 64 + 8 * (i div CHUNK)` gives **each worker
its own size class and therefore its own bin**. Same lock, different cache lines.
Interleaved min-of-3, compiler `c4a89282faa6`:

| workers | shared bin | distinct bins |
| --- | --- | --- |
| 1 | 0.14s | 0.17s |
| 2 | 0.22s | 0.23s |
| 4 | 0.33s | 0.34s |
| 12 | 0.45s | 0.57s |

**Distinct bins degrade as much as the shared one.** Cache-line sharing is not
the mechanism; the lock is. The summary's claim survives a test that could have
refuted it, which is the only reason it is now worth anything.

### The serialiser, confirmed at its source

Not inferred from the architecture — read. `compiler/ir_codegen.inc:8948`:

```pascal
else if procIdx = -Ord(tkGetMem) then
begin
  { GetMem or class instantiation. Evaluate size -> rax, then Alloc. }
  EmitAcquireHeapLock;
```

and the same at `:9059` for `tkFreeMem`. **On x86-64 the heap lock is emitted by
the COMPILER around the whole allocator call; it is not taken inside
`PXXAlloc`.** (`{$ifdef PXX_TS_SOFTLOCK}` inside `PXXAlloc` is the i386/aarch64
arm, where the locks live in Pascal — it is not compiled on x86-64.) So the
entire bin fast path runs under a global lock that a thread-local pop would not
need at all.

### The design consequence: do NOT push the lock into PXXAlloc

The obvious move — lock-free fast path inside `PXXAlloc`, take the lock on the
slow path — **deadlocks, and it deadlocks into the half the owner parked.**
`PXXAlloc` is also called from the managed string/dynarray emitters
(`ir_codegen.inc:194, 505, 525, 536, 557, 3411, 3515, 3539, 3560, 3579, ...`)
which already hold the lock across the call. A lock taken inside `PXXAlloc`
would be re-acquired by a holder, and the lock is not reentrant — which is
precisely why this ticket is *named* "reentrant heap lock **and** per-thread
arenas". The two halves are coupled in that direction, and the reentrancy half
is parked by the owner (2026-08-21, not to be re-litigated).

**The route that avoids the coupling entirely: put the fast path in the EMITTER,
not in `PXXAlloc`.** At the two sites above and nowhere else, emit inline:

1. read `__pxxTlsBase` (an existing intrinsic, x86-64-only — see above);
2. if the per-thread bin for this size class is non-empty, pop it, zero it, done
   — **no lock, no call**;
3. on miss, fall through to exactly today's code: `EmitAcquireHeapLock` + call
   `PXXAlloc`.

`FreeMem` mirrors it: push to the thread-local bin when the size header is
`<= HEAP_BIN_MAX`, else lock and call `Free`. Nothing else changes; every
managed-string site keeps today's lock and today's ordering, and `PXXAlloc`
itself is untouched, so no path can re-enter the lock. **Reentrancy stays
parked and stops being a prerequisite.**

Storage fits the four free TLS slots: **one** slot for a pointer to a
per-thread `array[0..HEAP_BIN_COUNT-1] of Int64` (`HEAP_BIN_MAX = 512` → 64 bins
→ 512 bytes, allocated once on first use through the normal locked path), and
optionally two more for a private bump region later. `TLS_SLOT_FIRST_FREE = 12`
of 16.

### What is NOT settled, and belongs to whoever implements it

- **Thread-exit drain.** Blocks parked in a dead thread's bins are unreachable
  to everyone else. Bounded (≤ 64 blocks × the sizes that thread freed) but it
  is a real retention and needs a flush at thread teardown or an explicit
  statement that it is accepted.
- **Zero-init contract.** The inline pop must zero the payload, because
  `PXXAlloc` guarantees zeroed memory on both of its paths and callers rely on
  it (managed headers, dynarray slots). The emitter arm must reproduce that
  guarantee, not assume it.
- **`-dPXX_HEAP_DEBUG` / `PXX_ALLOC_CENSUS` interaction** — both instrument
  `PXXAlloc`, which the fast path now bypasses, so a census would silently stop
  counting most allocations. A guard that cannot see the traffic prints a
  plausible small number rather than failing.

### ONE ALLOCATOR, settled 2026-09-01 — so there is no fork and no `decide-*`

Asked because "two allocators" would make this a `normalise-dont-special-case`
question (the second path is the one that stays broken, and three targets on an
unexercised path is how it stays broken silently). It is one.

**There is exactly one allocator: `compiler/builtin/builtinheap.pas`.** `lib/rtl`
has no heap unit, no `PXXAlloc`, and no `HeapPtr`/`HeapEnd` — checked by
definition site, not by filename.

The four `PXXAlloc` hits in that file are **one forward declaration plus three
mutually exclusive PROFILES**, and exactly one is compiled into any binary:

| lines | selected by | backing |
| --- | --- | --- |
| 115 | — | forward declaration |
| 1013 | `{$ifdef PXX_ESP_IDF}` | IDF `calloc`/`free` |
| 1064 | `{$else}{$ifdef PXX_LIBC_HEAP}` | libc `calloc`, debug only, "NOT for production" |
| 1172 | `{$else}` | **native** bump + size-class bins — the one measured above |

Both alternate profiles delegate to an allocator that already has its own lock
discipline, so arenas concern the native profile only.

**And the native `PXXAlloc` already carries a capability arm for exactly this
concern** — `{$ifdef PXX_TS_SOFTLOCK}` at 1176-1184, taking the spinlock inside
the function. Per-thread arenas are a second arm in a function that already has
one, gated on a target predicate in the shape of `TargetHasProcCleanupFrame`.
That is an ordinary Track A change, not a design fork: nothing on
i386/aarch64/arm32 becomes incorrect, they keep today's behaviour exactly.

### Two stale claims in the done ticket's "What this unblocks, and what is left"

[[feature-a-thread-local-storage-via-clone-settls]] says the remaining arena work
is `lib/rtl` — *"palthreadobj's launcher installing a block per TThread, and the
allocator magazine itself — which is Track B's file-lane, not A's"*. **Both
halves are wrong, and they are wrong in opposite directions.**

1. **The magazine is not Track B's.** The allocator is `compiler/builtin/`, which
   is Track A's file-lane. `lib/rtl` never had it.
2. **The launcher work does not exist at all.** `thread_emit.inc:79-85` installs
   the TLS block in the clone stub, before any Pascal runs, and says why that
   location was chosen: *"Doing it here rather than in the RTL launcher is what
   makes that unreachable: every pxx thread passes through this stub, whatever
   frontend or library created it."* Verified there is no other path —
   `palthread.pas` is the single M1 wrapper over `__pxxclone`, and
   `palthreadobj` (M3), `palparallel` and `palpthread` all build on it.

So the whole job is one lane, one file, one function. The lane split in that
ticket was the reason to suspect two allocators; it was a stale claim, not a
second allocator.

### What the work actually is



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
