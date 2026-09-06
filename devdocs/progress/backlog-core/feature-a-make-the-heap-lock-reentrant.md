---
slug: feature-a-make-the-heap-lock-reentrant
title: "Make the codegen heap lock reentrant — the half of the arena ticket the owner parked, now unparked by his own trigger"
track: A
type: feature
prio: 60
status: backlog
owner: frankH
created: 2026-09-06
found-by: owner (decision), vehicle filed by frankuser
blocked-by: []
summary: "DECIDED 2026-09-06 (decide-a-how-should-the-nilpy-managed-finalize-re-enter-the-heap-lock, arm (a)) and LANDED THE SAME DAY in three steps. The reentrancy half of feature-a-reentrant-heap-lock-and-per-thread-arenas -- parked by the owner 2026-08-21 with an explicit unpark trigger, 'a deadlock, or a new managed member kind whose release cannot be hoisted out of the lock' -- is unparked because a deadlock arrived. BSS_HEAP_OWNER/BSS_HEAP_DEPTH sit ON TOP of BSS_HEAP_LOCK, so the contended path and its exit-212 diagnosis are untouched; identity is EmitIoLockStubs' sequence (cached TLS tid, trusted only when rsp is inside that block's recorded stack bounds, else gettid), because gs:[0] is INHERITED across clone and recording the tid harder at thread start cannot help a thread that has no thread-start of ours. IT CLOSES TWO ROWS, MEASURED WITH A DISCRIMINATING CONTROL: the threadsafe dyn-array Variant/interface leak goes 7939 -> 3 live at the SAME allocation count, and the same program under -dPXX_NO_REENTRANT_HEAPLOCK hits rc=212 with the heap-lock diagnosis -- so the reentrancy is load-bearing rather than assumed; and the NilPy threadsafe class-field leak goes 19760 kB -> 1048 kB maxrss. THE COST OBJECTION HAD SUBSTANCE AND THIS SUMMARY USED TO SAY IT WAS NEVER MEASURED: it is +7% with the magazine on and +14% off, 1M construct/free iterations, min-of-5 interleaved, allocation-saturated upper bound on a shared box. Fork NOT re-opened -- the owner ruled with the objection in front of him. Narrowing avenue if it ever matters: only acquires inside a HeapLockedCallProcIdx1 region can nest, so every other site could keep the inline TTAS. STEP 2 SHIPPED A RACE AT 3bb71fd79 AND IT IS FIXED: the stamp was moved into EmitHeapLockStubs, which runs from the PROLOGUE before builtinheap.pas is parsed, so FindProc answered -1, the `if >= 0` guard silently did nothing, and the managed walk emitted with NO lock -- both test_threadsafe_class_finalize_* rows segfaulted 30/30. Resolution is at the CALL SITE now (Procs[procIdx].Name against the callee, which cannot answer -1 about a proc it is looking straight at); 30/30 green both rows, acceptance numbers unchanged. THE LESSON IS THE ASSERTION CLASS: restoring the CALL fixes the leak and the LOCK is a separate property, so every leak- and maxrss-shaped instrument I had improved identically with the acquire missing -- which the race test's own header had predicted in writing a week earlier."
---

# Make the heap lock reentrant

The decision is made — see
[[decide-a-how-should-the-nilpy-managed-finalize-re-enter-the-heap-lock]] for the
four grounds and the owner's words. **This ticket is the work, not the argument.**

## What it must handle

`PXXClassFinalizeManaged` runs under the codegen heap lock, reaches kind 6,
releases the inner object, and `PyObjFinalize -> PXXClassFinalize` calls
`PXXClassFinalizeManaged` again — acquiring a non-reentrant spinlock the same
thread already holds. **One instance, one thread, no contention.**

```python
class Inner:
    def __init__(self, s): self.s = s
class Outer:
    def __init__(self): self.f = Inner("hello")
o = Outer()
o = 0
```

**A wrapper-local depth counter does not work, and this is measured rather than
assumed:** the nested `PXXClassFinalize` runs its kind-4 pass, whose `FreeMem`
takes the lock at a **different codegen site**. Reentrancy has to live in the
lock primitive — owner plus depth — not in one caller.

## What it closes

| ticket | why it falls out |
| --- | --- |
| `bug-a-nilpy-under-threadsafe-still-leaks-every-class-field...` | its fix is BUILT and MEASURED (399524 kB → 7844 kB) and was reverted only for this deadlock |
| `bug-a-threadsafe-builds-leak-every-variant-and-interface-element-of-a-dynamic-array` | `ManagedElemKindLocked` degrades kinds 4 and 6 to 0 for the same reentrancy reason |
| record COM-interface fields | named at the bottom of that bug, same cause |
| `feature-n-nilpy-has-no-__del__...` | under a reentrant lock a user finalizer runs in place and may allocate |

## The measurement that attaches, and is NOT a gate

**The owner check's cost on the acquire path, min-of-N interleaved A/B,
post-magazine**, on x86-64 AND on one target that keeps the global lock. The
number the objection was argued from has never been taken. Record it either way.
**Do not re-open the fork on it without talking to the owner** — he ruled with
the objection in front of him.

## Sequencing

`__del__` lands **after** this, not before: building a user finalizer against a
lock that cannot re-enter is building against the deadlock. Once this is in,
`__del__` becomes the real adversary for it — a user finalizer that allocates
while the walk is running — which is a better test than the twelve-line repro.

## 2026-09-06 — taken by frankH, and the design, because the hard part is not the depth counter

**THE IDENTITY PROBLEM IS ALREADY SOLVED IN THIS TREE AND MUST BE REUSED, NOT
RE-DERIVED.** "Owner plus depth" needs a trustworthy answer to *which thread am
I*, and on x86-64 the obvious one is wrong: **`gs:[0]` is INHERITED across
clone**, so every thread pxx did not create — glibc `pthread_create`, which
`test/test_multithreading.pas` has used for months — reads the block of whoever
created it. gdb reported `gs_base = 0x411f98` for all five threads there, i.e.
`BSS_TLS_MAIN`. Taking that block's tid would answer *"the lock is already
mine"* for a lock this thread does not hold — **silent loss of mutual exclusion,
in the primitive whose entire job is mutual exclusion.** That is a strictly
worse failure than the deadlock we are fixing, and no content check catches it,
because inheritance reproduces the block byte for byte.

`EmitIoLockStubs` (`ir_codegen.inc`, the x86-64 arm ~1191, and the three ports
in `ir_codegen386.inc` / `_aarch64.inc` / `_arm32.inc`) already carries the
answer, from `feature-a-io-lock-owner-from-tls-not-gettid`: **trust the cached
`TLS_SLOT_TID` only when the reader's own `rsp` lies between the
`TLS_SLOT_STACK_LO` / `_HI` bounds that block's owner recorded**, and fall back
to a `gettid` syscall otherwise. The stack is the one thing inheritance cannot
fake. A `gettid` on every acquire is not an option here and was not there
either — measured at **43% of a 400k-Writeln run, one third of all syscalls**,
which is why that ticket exists.

### The shape that costs nothing on the fast path

The contended path is **already out of line** — `EmitHeapLockSlowStub`, a 5-byte
call the `jz` skips — and it is entered on exactly the two cases that matter:
contended, and re-entrant. So the *comparison* belongs there and is free.

What the fast path must still do is **record** ownership, and that is where the
cost objection actually lands. Proposal, no syscall and no atomic:

1. **Fast path, after winning the `xchg`:** load `gs:[0]`, check `rsp` against
   the block's `STACK_LO`/`_HI`, and only then set a per-thread
   *"I hold the heap lock"* flag in a free TLS slot. ~6 instructions, no
   syscall, no atomic, no lock-line traffic.
2. **Slow stub:** if that flag is set for the calling thread (same bounds
   check), this is RE-ENTRY — bump depth and return with the lock conceptually
   held. Otherwise spin exactly as today, including the 2^18 budget and the
   exit-212 diagnosis.
3. **Release:** decrement depth; clear the flag and store 0 to the lock word
   only at depth 0.

**The bounds check failing is FAIL-SAFE in the right direction.** A foreign
thread, a handler on the sigaltstack, or bounds nobody filled simply never sets
the flag, so it can never be granted false ownership — it spins and, if it truly
self-deadlocks, gets today's exit 212 rather than a corrupted free list. We
degrade to current behaviour exactly where identity is untrustworthy, which is
the property that makes this landable without solving foreign-thread TLS first.

`TLS_SLOT_FIRST_FREE = 13` and three map slots are free — **re-read that from
`defs.inc` rather than trusting this sentence**, it is a census with an owner
elsewhere and the numbers were one lower a fortnight ago.

### Scope note that shrinks the job

The codegen heap lock is **x86-64 only**: `EmitAcquireHeapLock` /
`EmitReleaseHeapLock` are `EmitAsmX64` in `ir_codegen.inc`, which is the x86-64
backend, and `EmitHeapLockSlowStub` refuses off x86-64 outright. The I/O lock is
the one that has four ports. So this is one emitter, not four — unlike the
cost measurement the ticket asks for, which still wants a target that keeps the
global lock.

### The measurement, restated now that the shape is known

With the recording moved to ~6 non-atomic instructions and the comparison out of
line, the number the objection was argued from is measuring something that no
longer exists in the proposal. **Take it anyway, min-of-N interleaved, and
record it either way** — and note the two instrument defines
(`-dPXX_ALLOC_CENSUS`, `-dPXX_HEAP_DEBUG`) turn the magazine OFF, so every
allocation under the leak instruments takes this lock and pays the recording.
That is a measurement-speed cost, not a shipped one, and it should be said out
loud rather than discovered.

## 2026-09-06 — STEP 1 LANDED: the reentrant layer, with what is and is NOT demonstrated

The owner+depth layer is in (`EmitHeapLockStubs`, `ir_codegen.inc`). **The
consumer half is not**, so this changes no program's behaviour yet — which is
the point of landing it separately.

### What it is

`BSS_HEAP_OWNER` (owning tid, 0 = free) and `BSS_HEAP_DEPTH` **on top of**
`BSS_HEAP_LOCK` rather than instead of it. `HeapLockSlowAddr` — the contended
path, its 2^18 spin budget and its exit-212 diagnosis — is untouched and still
reached, so the deadlock diagnosis survives for the cases that are still real
deadlocks (a foreign thread, a signal handler) while same-thread re-entry stops
hanging. The acquire became a 5-byte call because the identity check needs
registers and these sites sit mid-sequence with live values in rax, unlike the
I/O lock's statement boundaries; the stub saves and restores rax/rcx/rsi/r11.

Identity is `EmitIoLockStubs`' sequence, copied deliberately: cached
`TLS_SLOT_TID`, trusted only when the reader's own `rsp` is inside the block's
`STACK_LO`/`_HI` bounds, else a `gettid` syscall.

**The framing the owner arrived at independently, in the words that stop it
being re-proposed:** *"once we start a thread, we should record our id
somewhere"* — that is `TLS_SLOT_TID` and it is already done. The residual is the
half that proposal cannot reach: **a thread we do not start has no thread-start
of ours at which to record anything.** So the stack-bounds check is not a
cheaper way to get the id — **it is the only way to detect that the recorded id
is not yours.**

### VERIFIED

- `make compiler/pascal26` — `converged after 1 round(s)`, twice.
- `gate.sh quick` GREEN.
- `testmgr --tier native --job src:test/<f>.pas` GREEN on
  `test_multithreading`, `test_heap_magazine_foreign_thread` and
  `test_dce_threadsafe_heaplock`. The foreign-thread row is the one that matters:
  it is the population where `gs:[0]` is inherited.
- 1M-iteration `--threadsafe` allocation loop, rc=0, correct output.

### NOT VERIFIED, AND SAYING SO IS THE POINT

**The reentrancy is not yet exercised by a program that needs it.** I removed
the `{$ifndef PXX_TS_HARDLOCK}` at `builtinheap.pas`'s
`PXXClassFinalizeManaged(inst)` call as a probe, rebuilt, and ran the twelve-line
NilPy repro: rc=0 — **and so did the PINNED compiler on the same source.** So
that guard alone does not reproduce the deadlock, the control did not
discriminate, and I have NOT shown this layer fixes it. What is missing is the
second half of the reverted change: stamping `HeapLockedCallProcIdx1` once per
compilation so `PXXClassFinalizeManaged` is entered UNDER the lock on the NilPy
path, plus deleting the `Free` desugar's now-duplicate emission. That is step 2
and it is where the acceptance test lives.

### THE COST NUMBER, TAKEN AS INSTRUCTED, AND IT IS NOT ZERO

1M construct/free iterations, `--threadsafe -O2`, min-of-5 interleaved against
the pinned (non-reentrant) compiler, on a box also running two other seats'
testmgr — so treat these as an upper bound with real noise (the `before` column
ranged 2.40–3.49):

| | before | after |
| --- | --- | --- |
| magazine ON (shipped default) | 2.43s | 2.60s (+7%) |
| magazine OFF (`-dPXX_NO_HEAP_MAG`, every alloc takes the lock) | 2.40s | 2.74s (+14%) |

**The objection had substance and the ticket should stop saying it was never
measured.** It is now, on an allocation-saturated loop, which is the worst case
rather than a typical one. **Not re-opening the fork** — the owner ruled with the
objection in front of him, and this is recorded, not argued.

**The avenue if it ever needs to come down**, noted rather than taken: the
identity check is paid at EVERY acquire because any site could be the inner one.
Only sites reachable inside a `HeapLockedCallProcIdx1` region can actually nest,
so a reachability analysis would let the other sites keep today's inline TTAS.
That is a real optimisation and a real complication; it should follow a
measurement on a workload someone cares about, not this microbenchmark.

## 2026-09-06 — STEPS 2 AND 3: the consumers, and the control that was missing

### Step 2 — `PXXClassFinalize` finalizes its own managed fields again

`{$ifndef PXX_TS_HARDLOCK}` is gone from `builtinheap.pas`'s
`PXXClassFinalizeManaged(inst)` call, and `HeapLockedCallProcIdx1` is now
stamped **once per compilation** in `EmitHeapLockStubs` rather than lazily by the
`Free` desugar. Both of the desugar's duplicate second emissions are deleted —
the `Free` one and the caught-exception one this session added earlier — because
a second call is now a DOUBLE finalize, which is a double free rather than a leak.

Stamping once is the load-bearing half: `HeapLockedCallProcIdx1` keys on the
CALLEE, so one stamp wraps **every** call to `PXXClassFinalizeManaged` in the
lock, including the one `PXXClassFinalize` now makes itself. Stamped by the
desugar, a program that never desugars a `Free` never stamped it and the managed
walk ran unlocked.

NilPy under `--threadsafe`, 200000 constructions, maxrss:

| | |
| --- | --- |
| pinned (pre-change) | **19760 kB** |
| HEAD | **1048 kB** |

### Step 3 — `ManagedElemKindLocked` stops degrading kinds 4 and 6

The `if ThreadSafeMode then kind := 0` for COM interfaces and Variants is
deleted. That degradation existed because `_Release -> Destroy -> FreeMem`
re-entered the non-reentrant lock; it does not any more.

`test_threadsafe_dynarray_releases_variant_and_interface_elements.pas`, 1000
trips of each shape, `-dPXX_ALLOC_CENSUS`:

| | allocs | frees | live |
| --- | --- | --- | --- |
| pinned (pre-fix) | 13891 | 5952 | **7939** |
| HEAD | 13891 | 13888 | **3** |
| HEAD `-dPXX_NO_REENTRANT_HEAPLOCK` | — | — | **rc=212, the deadlock** |

Same allocation count on the two that finish, so it is the free side alone.

### THE THIRD ROW IS THE POINT, AND IT IS THE CONTROL STEP 1 COULD NOT PRODUCE

Step 1 shipped saying the reentrancy was not exercised by anything that needed
it, because the probe I had — removing the `{$ifndef}` and running the twelve-line
NilPy repro — gave rc=0 **and so did the pinned compiler on the same source**.
A control that does not discriminate. It was not a small probe, it was the wrong
population: that shape never re-enters.

`-dPXX_NO_REENTRANT_HEAPLOCK` is the A/B switch that fixes it — same tree, same
sources, reentrancy off — and it is kept, deliberately, as the positive control
and as a one-flag bisect, the same role `-dPXX_NO_HEAP_MAG` plays for the
magazine. **Lifting the degradation with it set makes this exact program hit
Runtime error 212, with the heap-lock diagnosis on stderr.** Checked the message
and not just the code, per frankuser's caution: a 212 arriving for another
reason would pass the control and prove nothing. Exit 212 has one producer,
`EmitHeapLockSlowStub`, and the stderr text names the heap lock.

### Still open, deliberately

Record COM-interface fields — the third row named at the bottom of the dyn-array
bug — are NOT done here. `builtinheap.pas` still carries two
`{$ifndef PXX_TS_HARDLOCK}` guards on `PXXRecordReleaseIntf` inside the
dyn-array-of-records walks. They are the same shape and should fall the same
way; they are left for a change that can measure them on their own rather than
riding in on a commit whose control is about elements.

## 2026-09-06 — THE STAMP WAS NEVER APPLIED, AND MY ACCEPTANCE TESTS COULD NOT SEE IT

`3bb71fd79` shipped a **race**. Both `test_threadsafe_class_finalize_race` and
`test_threadsafe_class_finalize_kinds` segfault at that sha, 30/30 on this box —
deterministic here, intermittent on seven. Caught by frankuser off the tstate
reports, not by anything I ran.

### What was wrong

Step 2 moved the `HeapLockedCallProcIdx1` stamp into `EmitHeapLockStubs`, which
runs from the **prologue** — before `builtinheap.pas` is parsed. So

```pascal
cfmPi := FindProc('PXXClassFinalizeManaged');
if cfmPi >= 0 then HeapLockedCallProcIdx1 := cfmPi + 1;
```

answered **-1** (printed, not inferred), the `>= 0` guard quietly did nothing,
and the stamp stayed 0. Every call to the managed walk then emitted with **no
heap lock around it**. Confirmed in the binary before reasoning about it: the one
call site in `PXXClassFinalize` was a bare `call 0x409e72`, `leave`, `ret`.

The comment eight lines below my own edit says this unit *"has not parsed yet"*.
It was correct, it was about exactly this, and I stamped there anyway.

### Why every instrument I had said green

**The call and the lock are two separate properties, and everything I measured
observed only the first.** Restoring the call is what fixes the leak; the lock is
what makes the walk safe. So `7939 -> 3 live`, `19760 kB -> 1048 kB` and the
`rc=212` control were all true, all reproducible, and all silent about the defect
— they improve identically whether or not the acquire is there.

`test_threadsafe_class_finalize_race.pas` says so in its own header, written
2026-08-31, a week before I broke it:

> the fix with the acquire removed, NT=4 → SIGSEGV (3/3)
> with the acquire removed the leak is still fixed, which is exactly why a leak
> probe alone could never have caught row 5

I re-created row 5 exactly, and my leak-shaped instruments certified it. The
header also states the design I violated: the lock is *"emitted at the call site
in ir_codegen.inc"*.

CLAUDE.md's rule is **match the assertion class to the defect class**. I did —
for the leak. The lock's defect class is a data race, whose only instrument is a
concurrent stress test, and `gate.sh quick` does not run the test-threads tier.

### The fix

Resolution moved to the **call site** (`IR_CALL`, `ir_codegen.inc`), against the
proc being called:

```pascal
if ThreadSafeMode and (TargetArch = TARGET_X86_64) and
   (HeapLockedCallProcIdx1 = 0) and
   (Procs[procIdx].Name = 'PXXClassFinalizeManaged') then
  HeapLockedCallProcIdx1 := procIdx + 1;
```

A name *lookup* can answer -1 about a table that is not populated yet. A
comparison against the callee you are emitting a call **to** cannot — the failure
mode that just shipped is structurally unavailable to it. One string compare per
emitted call until it matches, compile-time only.

Receipt, same program, after: `call 0x4001c0` (acquire) / `mov rax,rdi` /
`call 0x409e72` / `call 0x40022a` (release).

| | race | kinds |
| --- | --- | --- |
| `3bb71fd79` | 0/30 | 0/30 |
| fixed | **30/30** | **30/30** |

Acceptance rows re-measured after the fix and unchanged: 13891 allocs / 13888
frees / **3 live**, and `-dPXX_NO_REENTRANT_HEAPLOCK` still gives rc=212 with the
heap-lock text. Also green under `--threadsafe`: `test_multithreading`,
`test_heap_magazine_foreign_thread`, `test_dce_threadsafe_heaplock`,
`test_interface_byval_param_no_leak`, `test_interface_result_temp_leaks`,
`test_thread_heap_mixed`, `test_managed_dynarray_field_leaks`.

### The generalisation worth keeping

**A conservative guard converts a missing precondition into a silent no-op.**
`if found >= 0 then` reads as defensive and is indistinguishable, at the call
site, from "this never runs". The population is every `FindProc` in a
prologue-time emitter. Where the thing looked up is *required*, the guard should
be loud or the lookup should happen where the answer cannot be absent.

## 2026-09-06 — the third row closed too, so all three are done

"Still open, deliberately" above is no longer true. The two
`{$ifndef PXX_TS_HARDLOCK}` guards on `PXXRecordReleaseIntf` are lifted; that was
the record COM-interface-fields row. It waited for exactly this feature —
[[bug-a-array-of-records-with-interface-fields-leaks-the-interfaces]] named
`feature-a-reentrant-heap-lock-and-per-thread-arenas` in its own 2026-08-21
resolution as the condition for lifting it.

`test_interface_containers --threadsafe` is now byte-identical to the native row
(eight counts off 0), and `-dPXX_NO_REENTRANT_HEAPLOCK` gives rc=212 with the
heap-lock diagnosis at the first dyn-array walk. Three rows, three discriminating
controls, one feature.
