---
track: N
prio: 60
type: feature
owner: frankh-c0
blocked-by: []
status: working
created: 2026-09-20
found-by: frankb-8e
summary: "TWO PREMISES MEASURED AND BOTH FALSE; WHAT SURVIVES IS THE MISSING ENFORCEMENT. (1) THE THUNK DOES NOT ALLOCATE for the scalar case -- 100x the iterations gives +2 allocations (N=200 allocs=5, N=20000 allocs=7) against a positive control that scales exactly 100x (727 -> 72269), and even a `(const AnsiString): AnsiString` slot crosses allocation-free. THE ALLOCATION IS IN THE DEF BODY: `def grow(s): return s + 'x'` allocates ~1 per call. (2) THE JUSTIFICATION IS CONTRADICTED BY THE PLATFORM. This summary used to say an ISR that allocates is a latent crash that fires when the interrupt preempts code HOLDING THE HEAP LOCK. There is no such lock on either ESP profile. IDF: PXXAlloc is backed by calloc/free into heap_caps and multi_heap_platform.h:18 picks portmux spinlocks over RTOS mutexes BECAUSE malloc/free can happen in an ISR -- safe by deliberate design, the cost being latency and determinism. BARE: riscv32/xtensa are in neither the softlock nor hardlock target list, so there is no lock at all, and --threadsafe is REFUSED there rather than silently ignored; the free list is safe only BY UNREACHABILITY, since no interrupt handler can be installed on bare (the vector write is not expressible). SO THE MECHANISM, STATED SO IT DOES NOT DECAY WHEN AN INSTANCE IS FIXED: nothing refuses a def whose BODY can reach the allocator, and the thunk cannot fix that because the thunk is not where the allocation is. THE CONDITION THAT SPRINGS THE BARE HALF is the CSR/vector-install enabler LANDING, which converts bare from unreachable to reachable; at that point note that the remedy a seat will reach for is WORSE than the hazard -- PXXHeapSpin (builtinheap.pas:1611) is a bare xchg spin with no interrupt masking, so a task holding it and an interrupt contending for it on one core cannot make progress. ACCEPTANCE is a measured pair (must-reject `grow`, must-accept `two`), not the unsatisfiable 'reject the existing thunk once established that it allocates'. x86-64 only so far; the on-target context precondition is assertable via xPortInIsrContext and MUST be asserted as `<> 0` never `= 1` (riscv returns the raw nesting count, xtensa a normalised boolean). SPLIT OUT OF feature-n-a-nilpy-def-has-no-native-abi-entry-point-to-hand-to-a-c-callback 2026-09-20. Parent sits at 85 on a secondhand relay that the owner called ESP interrupts a must-have; this half is 60 because nothing downstream is blocked on it today."
---

# A non-allocating restricted thunk for an ISR

## Why this is separate rather than the next step of the parent

The parent ticket delivered a native-ABI entry point for a NilPy `def`: a
synthesized `$pycbthunk_<def>_<sig>` that carries the slot's signature and can
be stored where C or Pascal expects a code address. Two consumers landed
(argument site `2b28c3302`, store site `8dba4c72e`).

**That thunk marshals through Variants, and boxing a Variant is BELIEVED to
allocate** — inherited from the parent's prose and **not yet measured**; see the
first-measurement section, which found the IR readable and the proc-index→name
map missing.

**MEASURED 2026-09-21 AND FALSE FOR THE SCALAR CASE — the thunk does not
allocate per call.** See the premise section below for the differential and its
control. The allocation is in the def BODY.

**SUPERSEDED 2026-09-21 — THE PARAGRAPH BELOW IS THE CLAIM THIS TICKET WAS
FOUNDED ON AND IT IS FALSE ON BOTH ESP PROFILES.** It is kept because the
correction is about it; see "THE 'LATENT CRASH' JUSTIFICATION DOES NOT SURVIVE"
below. The heap lock it depends on does not exist on either profile.

An ISR that allocates is not a bug you find by running it. It is a latent
crash **with good latency numbers**: it works on the bench, and it fails when
the interrupt happens to preempt code holding the heap lock. That is
schedule-dependent, so a demo will not reproduce it and a soak test may not
either — which is exactly the profile of a defect that ships.

So the parent's shape does not extend here, and saying so is the point of the
split: **a reader who sees "the callback mechanism landed" will reasonably
assume the ISR case is a small follow-on, and it is a different contract.**

## What is wanted

A **restricted** thunk, with the restriction enforced rather than documented:

- fixed arity, known at compile time;
- scalar-only parameters and return — no Variant, no string, no container;
- no path to the allocator anywhere in the emitted body.

## The acceptance is a PROOF OF ABSENCE, which is the hard part

**`examples/esp32/nilpy-hw-c3` polling less is not evidence.** An allocating
ISR usually works, so a demo that runs proves nothing about the property this
ticket exists to establish. Asserting on behaviour here is the
assertion-class error this tree already records for leaks: the instrument
cannot physically observe the defect.

The claim has to be about the **generated code** — that the emitted thunk
contains no call that can reach the allocator. Candidate instruments, none of
them built or evaluated yet:

- a symbol-level assertion over the emitted thunk (does its call graph reach
  any `PXXAlloc`/`pybox`/carrier entry point);
- `PXXDBG=a.ir:<thunk>` read for allocation-shaped operations;
- a link-time check that the ISR-reachable set excludes the allocator.

**A positive control is mandatory and is the thing to design first**: a thunk
that DOES allocate must be rejected by whatever instrument is chosen, or the
instrument certifies the current shape as safe. The obvious candidate control is
the existing `$pycbthunk_` — **but only once it is ESTABLISHED that it
allocates.** Using an unverified control is the same error one level down: if it
turns out not to allocate, a check that passes it proves nothing and looks
green. **Establish the control's status before building the check that depends
on it.**

## Not established

Nothing here is measured. No repro, no inspection of the emitted thunk, no
allocation census of the current one. **The claim that the present thunk
allocates is inherited from the parent ticket's prose and should be MEASURED
before any design work** — it is plausible and it is not checked, and this
ticket would be pointless if it turned out false.

## Provenance

Split out 2026-09-20 while re-measuring the parent, which was sitting at p85
with an acceptance criterion its own body ruled out of scope. The owner called
ESP interrupts a **must-have** (relayed secondhand by frankuser, marked as
such, and the parent's 85 is his number). This half is ranked **60**: harder,
less specified, and nothing downstream is blocked on it today.

## Gate

Whatever instrument is chosen must reject the existing `$pycbthunk_` and
accept the restricted one, and the rejection must be demonstrated rather than
assumed.

## FIRST MEASUREMENT, 2026-09-20 — the artefact is reachable, the INSTRUMENT IS NOT COMPLETE, and it nearly handed me a fabricated finding

Compiler `3c6e31f94a62`. `PXXDBG='a.ir:*'` on `test/test_nilpy_def_into_a_native_callback_slot.npy` dumps **four** minted thunks and their IR is short and readable:

    PXXDBG a.ir $pycbthunk_2232_2218
    IR count=21
    ...
    12: call a=64    b=11 c=-1 ival=1 tk=0
    14: call a=2232  b=4  c=13 ival=0 tk=22
    16: call a=1206  b=15 c=-1 ival=0 tk=13

So the shape is: **three calls, one of which (`a=2232`) is the def itself** — the thunk name embeds `realPi`, so that one is self-identifying — and **two runtime helpers, `64` and `1206`**, with Variant-typed (`tk=22`) temporaries around them. **That is the whole question this ticket asks: what are 64 and 1206, and can either reach the allocator.**

**I COULD NOT ANSWER IT, AND THE WAY I ALMOST DID IS THE PART WORTH RECORDING.** There is no proc-index→name map in the instruments to hand, so I tested the obvious hypothesis — that `a.ir:*` dumps in proc-index order, making header *N* proc *N*. It gives:

    header #64   -> PXXRecordInitialize
    header #1206 -> TPyBytes.append

**Both are wrong, and both are plausible.** `PXXRecordInitialize` and `TPyBytes.append` are exactly the kind of runtime helper a thunk might call, and **`TPyBytes.append` ALLOCATES — it would have CONFIRMED this ticket's central premise.** I would have written "measured: the thunk calls an allocating helper" and it would have read as the strongest line in the file.

**The control that refuted it costs one number: `a.ir:*` emits 1921 headers and the IR references proc index 2232.** A dump of 1921 procs cannot be an index-ordered map covering index 2232, so the mapping is impossible, not merely unverified. **Not all procs are dumped** — dead ones are elided — so dump position and proc index are different coordinates that happen to be the same KIND of number.

**THIS IS THE POSITIVE-CONTROL PROBLEM ARRIVING BEFORE ANY ASSERTION EXISTS.** The instrument did not error. It answered, in the right format, with names of the right shape, in the direction I expected. Its population is *dumped* procs; my subject is indexed by *all* procs.

**SO THE FIRST DELIVERABLE HERE IS NOT THE THUNK, IT IS THE MAP:** a way to resolve a `call a=<n>` target to a routine name. Without it the IR dump shows the call graph in a coordinate system nothing else in the tree speaks, and any claim about what a thunk reaches is guesswork wearing a proc number. With it, the allocation question is probably a short afternoon.

**AND THE PREMISE REMAINS UNMEASURED.** The `tk=22` temporaries are suggestive of Variant marshalling and are not proof of a heap allocation — a Variant in a stack temporary need not allocate. **Nothing here yet establishes that the current thunk allocates.** That is still inherited from the parent ticket's prose, and this ticket is pointless if it is false.

## THE PREMISE IS MEASURED AND IT IS FALSE FOR THE SCALAR CASE (frankH, 2026-09-21)

This ticket's `Not established` section asks for exactly one thing first: *"The
claim that the present thunk allocates is inherited from the parent ticket's
prose and should be MEASURED before any design work ... this ticket would be
pointless if it turned out false."* Measured, with the positive control built
before the result was read.

**Instrument:** `-dPXX_ALLOC_CENSUS`, whose `pxx-census:` line reports
allocs/frees/live. **Population and tree:** x86-64, HEAD at pxx@04be5c412,
compiler byte-identical to pin v414 (`aeadb1754b80`).

**Method is a DIFFERENTIAL with the route varied and the subject held fixed** —
the same loop, the same call site, the same `cbslot.pas` slot, differing only in
whether the callee is a NilPy `def` (thunked) or a Pascal routine (plain
address). And the load is varied by TWO ORDERS OF MAGNITUDE, because a single N
cannot distinguish "does not allocate" from "allocates a constant".

    thunked   (def two(a,b): return a+b)      N=200 -> allocs=5      N=20000 -> allocs=7
    native    (cb.TheMaker, no thunk)         N=2000 -> allocs=8
    CONTROL   (a loop that must allocate)     N=200 -> allocs=727    N=20000 -> allocs=72269

**100x the iterations, +2 allocations.** The control scales exactly 100x, so the
instrument demonstrably sees per-iteration allocation and the thunk's flat line
is a measurement rather than a blind spot. **The existing `$pycbthunk_` does not
allocate per call for a scalar signature.**

### AND THE ALLOCATION IS IN THE DEF BODY, NOT IN THE MARSHALLING

Followed up because "no allocation" on a scalar slot does not yet say where
allocation WOULD come from. A second slot shape, `function(const s: AnsiString):
AnsiString`, in a scratch unit so no green fixture was touched:

    def ident(s): return s          N=200 -> allocs=3     N=20000 -> allocs=5
    def grow(s):  return s + "x"    N=200 -> allocs=196   N=20000 -> allocs=19780

**`ident` was nearly a false negative and is kept as the lesson**: it returns the
literal unchanged, so it never reaches the allocator and would have "confirmed"
that string thunks are allocation-free. Only forcing a concatenation exercised
the route. *Does my probe reach the thing under test BY THE ROUTE under test?*

So even an **AnsiString** parameter and return cross the thunk without
allocating. The ~1-per-iteration allocation in `grow` is the def BODY doing
allocating work.

### What this does to the ticket

**The wanted object largely EXISTS.** `What is wanted` asks for fixed arity,
scalar-only parameters and return, and no path to the allocator. For a scalar
signature the emitted thunk already meets the third — measured, not read.

**What is missing is the ENFORCEMENT, which is the half the ticket said matters:
"the restriction enforced rather than documented".** Nothing today refuses a def
whose body allocates, and a body is where the allocation demonstrably is.

**The positive control the `Gate` section demands is now established rather than
assumed**, and it is not the one the ticket guessed. The ticket proposed
rejecting the existing `$pycbthunk_` *"but only once it is ESTABLISHED that it
allocates"* — it does not, so that control would have been unsatisfiable and a
guard built on it would have had nothing to reject. The working pair is:

    MUST REJECT : def grow(s): return s + "x"     ~1 allocation per call
    MUST ACCEPT : def two(a, b): return a + b     flat across 100x

### Scope limits, stated rather than left to be assumed

- **x86-64 only.** Nothing here is measured on xtensa or riscv32, and this is an
  ABI-adjacent property, so the 64-bit host is exactly where a width- or
  convention-dependent difference would be invisible.
- Two slot shapes measured: `(Integer, Integer) -> Integer` and
  `(const AnsiString) -> AnsiString`. **Variant-parameter slots not measured.**
- The census samples on a geometric threshold, so the absolute counts are
  approximate. The 100x/flat CONTRAST is not: it is two orders of magnitude.

## THE "LATENT CRASH" JUSTIFICATION DOES NOT SURVIVE ON THE IDF PROFILE (frankb-8e, verified independently by frankH 2026-09-21)

Both citations read in the tree on this box rather than taken on report,
because they contradict this ticket's own stated reason to exist.

**(1) On the IDF profile, pxx's allocator IS the IDF heap.**
`compiler/builtin/builtinheap.pas:1391`, `{$ifdef PXX_ESP_IDF}`, in its own
words: *"the pxx heap is backed by the IDF heap — calloc/free externals resolve
to newlib/heap_caps at IDF link time"*, with `HeapMmap` never called. `EspArena`
is the BARE profile only. So a pxx allocation in an IDF-profile ISR is a
heap_caps allocation.

**(2) The IDF makes malloc/free ISR-safe deliberately.**
`components/heap/multi_heap_platform.h:18-19`, verbatim:

    /* Because malloc/free can happen inside an ISR context,
       we need to use portmux spinlocks here not RTOS mutexes */

and the macro below it uses `portENTER_CRITICAL_SAFE`, the ISR-safe variant.
The IDF did not tolerate allocation in an ISR; it chose its locking primitive
FOR it.

**So "an ISR that allocates is a latent crash" — the sentence in this ticket
and in its parent — is contradicted by the platform's own source on the profile
this work targets.** The real cost there is **latency and determinism**: a
spinlock and a critical section inside an interrupt handler. That is still a
good reason to forbid allocation in a real-time path, but it is a DIFFERENT
argument, with a different enforcement and a different acceptance, and the
ticket must not keep asserting the stronger one.

### THE PROFILE SPLIT MUST NOT BE COLLAPSED — "may a pxx ISR allocate" has at least two answers

**IDF profile: answered, by the platform, safe-but-costly.**

**Bare profile: OPEN.** There pxx uses its own `EspArena` and nothing in the
IDF's answer travels to it.

**A LEAD ON THE BARE HALF, AND IT IS A LEAD AND NOT A FINDING.**
`builtinheap.pas:1050-1059` records that the hard lock *"is emitted by the
CODEGEN around the tkGetMem/tkFreeMem sites (EmitAcquireHeapLock,
ir_codegen.inc) and PXXAlloc does not take it — so an allocation reached from a
Pascal HELPER (PXXObjAlloc -> PXXAlloc ...) held nothing"*. If that still holds,
then on the bare profile a concurrent allocator entry has no mutual exclusion on
the free list, and an ISR is a concurrent context — which would put the
corruption argument back, but located precisely and only on bare.

**NOT VERIFIED BY ME.** That comment is describing a threading bug with its own
measurement date and I have not established what the tree does today, nor that
the thread case transfers to the interrupt case. Recorded so the next reader has
the thread to pull, explicitly not as a result.

## THE PRECONDITION IS ASSERTABLE, AND THE ASSERTION MUST BE `<> 0` NOT `= 1` (frankb-8e)

`BaseType_t xPortInIsrContext(void)` is an ordinary IDF external, so pxx can
call it and the fixture can ASSERT the context rather than claim it in a
comment. **The two ports return different quantities:**

    riscv   port.c:461/469  return port_uxInterruptNesting[coreID];      RAW COUNT
    xtensa  port.c          return (port_interruptNesting[coreID] != 0); NORMALISED

So under nesting riscv legitimately answers 2 or 3 where xtensa answers 1, and
an `= 1` row is a cross-target trap that the esp32c3 arm alone cannot reveal —
**correct on every run until a second interrupt arrives during the first.** The
variable is even spelled differently per port (`port_uxInterruptNesting` vs
`port_interruptNesting`), so a grep for one finds half the story.

**Row design, therefore: assert the ASYMMETRY as predicates, not values** —
task-dispatch reads 0, ISR-dispatch reads NON-ZERO, on both chips. Portable
across both ports, survives nesting, and the single asymmetry validates the
instrument and the precondition together. A raw nesting count is a separate
observational row and is **riscv-only**, because xtensa cannot produce it.

**Why the asymmetry and not an absolute value:** a probe that only ever reads 0
cannot distinguish "both are task context" from "the instrument always returns
0". That is the guard-that-cannot-fail shape, and the discriminating half lives
in this ticket's arm.

### THE TASK-CONTEXT BASELINE IS MEASURED ON BOTH ISAs (frankb-8e, 2026-09-21)

    esp32c3 (riscv32)   app_main in-isr=0   timer-callback in-isr=0   (all 398)
    esp32s3 (xtensa)    app_main in-isr=0   timer-callback in-isr=0   (all 392)

So `xPortInIsrContext` is callable from Pascal on both ports, and the ordinary
esp_timer callback is task context **by measurement on both**, not merely by the
source comment. The 398/392 difference is a fixed wall-clock window against a
100 ms periodic timer and is **not a signal**.

**AND THE BASELINE DOES NOT VALIDATE THE INSTRUMENT — 8e SAYS SO ITSELF AND IS
RIGHT.** Four zeros across two ISAs are exactly as consistent with *"the
function always returns 0"* as two zeros were: more rows of the SAME arm add
confidence about that arm and none about the instrument. **A wider clean sweep
is the more seductive version of the trap, because it reads like
corroboration.** Only the ISR-dispatch row in THIS ticket's arm can produce a
non-zero, so the guard-that-cannot-fail is discharged here or nowhere.

**The riscv nesting quantifier is verified in source, not inferred**:
`portasm.S:607` branches on it in terms — *"If we reached here from another
low-priority ISR, i.e, port_uxInterruptNesting[coreID] > 0, then skip stack
pushing to TCB"*. So a `= 1` row is a live trap on that port and not a
theoretical one.

**`iram;` does its placement job**: `MyIsr` in `test_esp_isr_register.pas`
resolves to `.iram1.text` on the IDF object, same as an `interrupt;` body. (Both
emit symbol size 0, which matters to nothing here but would matter to any tool
reading FUNC sizes.)

### THE BARE LEAD IS RESOLVED, AND THE PROFILE SPLIT'S TWO HALVES ARE OPPOSITE (frankb-8e 94ba410fa + frankH)

The lead above is settled and it was understated. It is not that `PXXAlloc`
misses the codegen hard lock on ESP — **there is no lock model on ESP at all**:

    frontend_prologue.inc:127   EmitHeapLockSlowStub  <- ThreadSafeMode AND TARGET_X86_64
    paslexer.inc:1226           PXX_TS_SOFTLOCK       <- i386 / aarch64 / arm32
    paslexer.inc:1242           PXX_TS_HARDLOCK       <- x86-64

riscv32 and xtensa are in **neither** list, and the flag is not silently a
no-op: `--threadsafe --target=riscv32 --esp-profile=bare` is REFUSED with *"the
heap/ARC/I-O locks are not implemented on this target yet"*. The compiler is
being honest.

So: **IDF — safe, by the platform's deliberate design. BARE — unlocked, and
safe only BY UNREACHABILITY**: no FreeRTOS, and no interrupt handler can be
installed on bare at all because the vector write is not expressible, so
nothing can currently interrupt an allocation. The hazard is **latent, not
live**, which retires the on-target allocation-call census — its condition is
met and its consequence is not. What refires it is the CSR enabler LANDING,
because that is the commit that converts the bare cell from unreachable to
reachable.

### AND THE OBVIOUS REMEDY IS WORSE THAN THE HAZARD ON A SINGLE CORE (frankH)

Recorded here because a seat that reads *"unlocked allocator"* as the finding
will reach for the fix the source itself offers, and it is a trap.

`builtinheap.pas:1611` — under `PXX_THREADSAFE` the allocator's lock is a bare
exchange loop with **no interrupt masking**, released by a plain store:

    while Integer(__pxxatomic_xchg(@PXXHeapSpin, 1)) <> 0 do tsIgnore := tsIgnore + 1;

Wire riscv32 into the softlock list once interrupts are reachable and that is
not a partial fix, it is a **deadlock**: a task takes the spin, an interrupt
preempts it, the handler allocates and spins forever on a lock whose only
possible releaser is the task it is standing on. Neither can make progress.
Unlocked corrupts a free list, which is survivable and debuggable; this hangs
the chip silently.

**The platform already decided the shape of any eventual ESP lock, and it is
not this one.** The operative half of the IDF line both of us quoted is its
ending: *"we need to use portmux spinlocks here **not RTOS mutexes**"*, with
`portENTER_CRITICAL_SAFE` — which DISABLES INTERRUPTS. The IDF is not picking a
spinlock for speed; it is picking the one primitive that closes this hole, and
`PXXHeapSpin` is the primitive it rejected.

**Stated as a mechanism and not as a prohibition** — "a plain spin taken by a
task and contended by an interrupt on one core cannot make progress" survives
someone renaming the flags, where "do not enable threadsafe on ESP" does not.

## THE ASYMMETRY IS WITNESSED — `examples/esp32/isrctx-c3`, esp32c3 under QEMU, 2026-09-21

    PXX isrctx: main ctx=0
    PXX isrctx: task hits=5 ctx=0
    PXX isrctx: isr  hits=5 ctx=1
    PXX isrctx: PAIR OK status=0
    OK   isrctx-c3 qemu acceptance -- task ctx=0, ISR ctx=1 (asymmetry witnessed)

**ONE IMAGE, ONE BOOT, BOTH DISPATCH METHODS.** The only declared difference
between the two callbacks is the `dispatch_method` byte in
`esp_timer_create_args_t`; same instrument, same binary, microseconds apart.
Two separate runs would have compared two images and two boots.

**What this settles, and it is the thing neither arm could settle alone:**
`xPortInIsrContext` is a LIVE instrument on riscv32. frankb-8e's four clean
task-context rows across two ISAs (~400 callbacks each) were consistent with
*"every context here is task context"* AND with *"the function always returns
0"*, and no number of further zeros could separate those. The `ctx=1` row does,
so 8e's baseline is retroactively a measurement rather than a possible
artefact. **The guard-that-cannot-fail is discharged, and it was discharged in
the arm that can produce a non-zero — the only one there is.**

**And it agrees with the platform's own expectation**, which is an independent
check I did not have to write: `esp_timer.c:470` has the IDF itself asserting
`xPortInIsrContext()` inside the ISR-dispatch path. Our reading is what the
IDF's own code requires of that path.

**So a pxx `iram;` routine reached through `ESP_TIMER_ISR` genuinely runs in
interrupt context.** That is the precondition this ticket's restriction exists
to protect, and it is now a measured fact rather than a design intention.

### What the fixture does NOT witness

QEMU is not silicon — timing, the real peripheral and anything analog are
untouched. It is riscv32 only; **the xtensa arm would read `1` for a different
reason** (that port normalises to a boolean) and is not run here. The `1` is
printed as an observation and never asserted: the assertion is `<> 0`, because
riscv returns the raw nesting count and a row pinning `1` would be correct on
every run until a second interrupt arrives during the first.

Nothing here measures allocation. It establishes the CONTEXT, not the contract.

## THE ENFORCEMENT: WHERE IT GOES, AND THE ONE DESIGN DECISION THAT DECIDES WHETHER IT WORKS

The measurement relocated this. `PyDefFitsCallbackThunk` (`pyparser.inc:17566`)
already decides whether a def may be thunked at all, and what it checks is the
SIGNATURE — arity, all-`tyVariant` params, a user def rather than pylib, the
plain function-value carrier with a nil receiver. Every one of those is a fact
about the interface.

**The ISR restriction is a fact about the BODY, and there is no predicate for
that.** That is the gap, stated as the thing to build rather than as the thing
that is missing.

### THE POLARITY IS THE WHOLE DESIGN, AND THE OBVIOUS ONE IS WRONG

The natural implementation is a scan of the def's emitted IR for calls to the
allocating helpers — `PXXAlloc`, `PXXObjAlloc`, the string and container
builders — refusing if any appear. **That is a BLACKLIST, and for a safety
property the polarity is backwards.** A blacklist that misses one allocating
helper does not fail loudly; it ACCEPTS an allocating def and hands it to an
interrupt. The failure mode of the guard is the exact outcome the guard
exists to prevent, and it is silent.

**So: refuse unless EVERY call target in the body is on an allow-list of
primitives established not to allocate.** A new or renamed helper is then
refused by default. The guard fails toward rejection, which is recoverable — a
def that should have been accepted produces a diagnostic somebody reads —
where the other polarity fails toward a latent defect on a target nobody is
debugging interactively.

This is the same shape as the `SizeOf`-default and empty-aggregate collisions:
**ask what the guard does when the machinery has not been taught about
something.** A blacklist says yes.

### The acceptance pair, restated against this design

- **must-reject** `def grow(s): return s + 'x'` — measured to allocate ~1 per
  call, so a guard that accepts it is demonstrably wrong.
- **must-accept** `def two(a, b): return a + b` on a scalar slot — measured to
  cross the thunk allocation-free, so a guard that refuses it is demonstrably
  over-strict and the feature is useless.

**Both rows are required and for opposite reasons**: the first is the positive
control (a guard that cannot reject anything is not a guard), the second is the
control against the trivially-safe implementation that refuses everything (a
gate that cannot pass is not a gate). Either alone can be satisfied by a
one-line lie.

### Not yet built. What is NOT blocking it

The context precondition is settled — `isrctx-c3` witnesses that an `iram;`
routine on `ESP_TIMER_ISR` runs in interrupt context — and the profile
question is settled by the sections above. Neither was blocking this, and
saying so matters because both are the kind of open question a seat parks work
behind.


## THE DCE-BASED CLASSIFIER DOES NOT WORK, AND THE NEGATIVE CONTROL IS WHAT SHOWS IT (2026-09-21)

frankb-8e proposed the classifier with the right polarity in mind: compile a
program whose only content calls primitive P, build with `--dce`, and ask
whether `PXXAlloc` SURVIVES. DCE over-approximates reachability, so an absent
`PXXAlloc` would be a sound proof that P cannot allocate. The reasoning is
correct. **The instrument is not, and it fails in the way this tree keeps
recording: it cannot produce the answer that would clear anything.**

    program                       is PXXAlloc live?
    x = 1                    (npy)      YES
    print(1)                 (npy)      YES
    def two(a,b): a+b        (npy)      YES
    def grow(s): s+'x'       (npy)      YES
    program min; a := 1      (pas)      YES
    program allocp; s+'x'    (pas)      YES

**`PXXAlloc` is live in EVERY image, including a program that declares one
integer and assigns it.** The chain is identical in all six and does not
mention the subject:

    PXXAlloc <- PXXStrLoadFile <- [called from unowned code]

`PXXStrLoadFile` is reached from unowned code, which DCE must treat as a root.
So `PXXAlloc`'s survival is **a property of the RTL's root set, not of the
program's body**, and no program can ever make it die.

### Why both arms looked asserted

**The must-reject arm passes, and it passes for a reason that has nothing to do
with the def.** `def grow(s): return s + 'x'` does allocate, the probe does say
`PXXAlloc` is live, and the two facts are unrelated — the empty program says
the same thing. That is a positive control drawn from the wrong population
certifying a broken instrument, and it is undetectable from the reject side
alone.

**The control that exposes it is the NEGATIVE one — the empty program — and
nothing in the design called for running it.** A classifier is naturally tested
on a thing that should pass and a thing that should fail; the thing that should
fail *for no reason at all* is the third row, and it is the only one that
discriminates. Recorded here because the next seat will reach for this
classifier again: **it is not that the probe is noisy, it is that the probe
cannot emit the answer the allow-list needs.**

### What it would have done to the feature

Since `PXXAlloc` is never absent, no primitive is ever certified safe, the
allow-list comes out EMPTY, and the guard refuses every def. That is the SAFE
direction — which is why it would have survived review — and it makes the
must-accept row (`def two(a, b): return a + b`) fail. **A gate that cannot pass
is not a gate**, and this one would have arrived looking appropriately
conservative.

### The instrument the property actually needs

The question is not "is the allocator in the image". It is **"can THIS proc
reach the allocator"** — reachability from a chosen root, forward, over the
call graph. That graph already exists and is exact for internal direct calls:
`dce.inc`'s header records that `EmitCallProc` puts EVERY internal direct call
in `CallFix`, precisely so the pass can walk it, and DCE is a post-pass running
after all emission, so a def's body is complete by then.

No flag exposes a forward query. `--dce-why=<substr>` walks UP from a live body
to the reason it is live, rooted at the program's roots; this needs a walk DOWN
from one named proc. That is the next thing to build, and it is small.

**Caveat to carry into it, from `dce.inc`'s own header:** the graph is exact
for direct calls, and indirect ones (`@proc` taken, vmt/rtti slots) are
conservative ROOTS rather than edges. For an allow-list that is the right way
round — an indirect call inside a candidate body must make it refuse — but the
predicate has to actually treat "body contains an indirect call" as a refusal
rather than as an absence of edges, or it will read an unknown as a clean walk.

## THE FORWARD QUERY IS BUILT, AND IT IS NOT YET USABLE AS THE GUARD (2026-09-21)

`--dce-reach-from=<name>` landed at `8007a358b`. It walks the call graph
FORWARD from one named body, reusing the edge list `DceRun` already
counting-sorts out of `CallFix`. It prints a reachable SET and refuses to print
a verdict, and an unresolvable name is a loud refusal rather than an empty set.

**Sound, verified against a `-O0`/`-O2` pair before any use:**

    -O0   Top -> {Leaf, Mid}   Mid -> {Leaf}     transitivity holds
    -O2   Top -> {Mid}         Mid -> {}         the inliner really removed it

**And it cannot answer this ticket's question yet, for a measured reason:**

    function Leaf(x: Integer): Integer;
    begin g := g + 'x'; Leaf := x + 1; end;    { g: global AnsiString }

    --dce-reach-from=Leaf   ->  0 bodies
    --dce-why=PXXStrAppend  ->  PXXStrAppend <- [called from unowned code]

**A body that provably allocates reports zero reachable bodies** — the wrong
polarity for the third time on this question in one day.

### The mechanism, settled rather than guessed

The zero-width-body candidate is REFUTED. Give `Leaf` a real call beside the
concat and the walk finds it (`-> 1 body: Pure`), so `Leaf` owns a range and
`ProcBodyEnd` is recorded. Exactly one hop is missing:

    Leaf  --CodeRef-->  stub (unowned region)  --CallFix-->  PXXStrAppend

A CodeRef names a code OFFSET, not a proc, so it is not an edge in this graph;
the stub's own call to `PXXStrAppend` *is* a `CallFix` entry, but its site is in
unowned code and is therefore a ROOT. **Both halves of the path exist and the
join does not.**

**What it needs:** stub regions as pseudo-nodes — an id per CodeRef target
(`DceAddStubTarget` already collects them), an edge from the owning body to
that id, and edges from the id to the `CallFix` targets whose sites fall inside
it. That is the next piece of work on this ticket.

### The refusal half, corrected by frankb-8e and better than my version

My phrasing was "refuse if the body contains an indirect call". **That
under-reaches.** `p := @Foo` with no call in sight must still refuse: the root
`@Foo` creates is GLOBAL and is not an edge out of the body that created it, so
a forward walk from that very body walks clean and certifies it. The predicate
must fire on **"this body TAKES AN ADDRESS, or installs a body in a dispatch
slot"**, not on "this body calls through a pointer".

**A real positive control exists for that half and beats a fixture:**
`bug-nilpy-a-python-override-of-a-virtual-pascal-method-segfaults-...`
(backlog-nilpy) puts a Python method body in a Pascal vtable slot, entered by a
virtual call from Pascal. **No edge anywhere in the graph expresses that
crossing**, so it is precisely the shape that would certify clean and be wrong,
and it fails at run time for an unrelated reason — which makes it a clean
subject for a static question.

### Status

Two instruments proposed for this ticket and both refuted before anything was
built on either: the absolute form (`is PXXAlloc live`, `68a15c4d4` — and 8e
has since shown it DOES discriminate on ESP riscv32 `--emit-obj`, so the two
results differ by root set rather than contradicting, and both are carried),
and now the forward form's stub-hop gap. **Neither refutation cost more than
twenty minutes, and both were found by running a control the design did not
call for.**

## THE STUB GAP IS CLOSED, AND THE POLARITY IS NOW RIGHT (2026-09-21)

`--dce-reach-from` now models unowned code as ONE node, so a body that calls a
runtime stub may reach whatever unowned code calls. **The allocating body no
longer reads clean.**

    --dce-reach-from=Leaf   before:  0 bodies
                            after:   38 bodies (0 direct, 38 via unowned code)
                                     including PXXAlloc   [via unowned code]

**frankb-8e's five-body table, which is the acceptance test**, reproduced here
independently with the build asserted first:

    body          before          after
    PlainOnly     1    no         1    no      <- must NOT move, and does not
    UsesNew       8    YES        8    YES
    UsesSetLen   25    YES       25    YES
    UsesCopy      2    no        53    YES     <- was wrong
    UsesConcat    1    no        53    YES     <- was wrong

**`PlainOnly` staying at 1 is the control that makes the other rows worth
reading** — it shows the merge did not collapse into
everything-reaches-everything. Without it, "all five now say YES" would be
indistinguishable from a guard that cannot pass.

### 8e's shape, which is why this was fixable at all

**Object creation and dynamic-array growth already recorded their edges; STRING
operations did not.** So the gap was never "synthesised helper calls are
invisible to the graph" — it was one lowering path whose call sites belong to
no body. My own statement of it ("the concat is emitted outside the body
range") was too narrow and 8e's table refuted it: the same thing happens to
`WriteLn` and does not happen to `SetLength`.

8e also killed the alternative reading before reporting: if the concat were
lowered inline with no call at all, "no edge" would be CORRECT and the
liveness would come from elsewhere. `--dce-why=PXXStrAppend` answers
`PXXStrAppendAsciiBits <- PXXStrAppend <- [called from unowned code]`, so there
IS a call site and it is attributed to no body. A lost edge, not an absent
call.

### What the approximation costs, stated rather than buried

All stubs are one node, because `DceStubTgt` holds entry offsets and no
extents, and inventing extents would be a guess inside a reachability answer.
So a body calling any stub appears to reach everything any stub calls: a false
YES is possible, a false NO is not. **That is the direction a safety question
wants**, and those rows print as `[via unowned code]` so the approximate half
of an answer is visible at the point of use rather than in a ticket.

The string rows going 2 -> 53 and 1 -> 53 is that cost, in the open.

### Still open for the guard

The refusal half — 8e's corrected predicate, fire on **taking an address or
installing a body in a dispatch slot**, not on "calls through a pointer" — is
not built. Its positive control is named:
`bug-nilpy-a-python-override-of-a-virtual-pascal-method-segfaults-...`.

### THE MERGE'S SOUNDNESS IS NOT THE TOOL'S, AND THERE IS A MEASURED FALSE NO

frankb-8e caught the sentence above before anything was built on it. "A false
YES and never a false NO" is true of **the merge** — collapsing unowned code to
one node can only ADD reachability, so it cannot manufacture a NO — and a
reader hears it as a property of **the answer**. It is not one.

**Measured, hosted, `-O0`, build asserted:**

    function Allocs(x: Integer): Integer;
    begin g := g + 'x'; Allocs := x + 1; end;
    function TakesAddr(x: Integer): Integer;
    begin hook := @Allocs; TakesAddr := x + 1; end;   { calls nothing }

    --dce-reach-from=TakesAddr  ->  0 bodies, PXXAlloc: no    <- FALSE NO
    --dce-reach-from=Allocs     ->            PXXAlloc: YES   <- control

`TakesAddr` installs an allocating routine in a dispatch slot and comes back
**clean**. The root `@Allocs` creates is GLOBAL and is not an edge out of the
body that created it, so a forward walk from that very body walks clean.

**For "does this ISR allocate", the false-NO direction is the one that hurts,
and it is entirely the refusal half's job.** So the refusal half is the
load-bearing piece, not polish — which is precisely how it would have read if
the merge's soundness had been left standing as the tool's. **A NO from this
tool is not a safety claim today**, and that sentence is now in the tool's own
comment rather than only here.

### THE @proc FALSE-NO CHANNEL IS CLOSED; THE VMT ONE IS NOT

A body that takes an address now gets an edge to what it took the address of.
A pointer's value has to come from somewhere, so this is the conservative
reading of "this body can cause that to run".

    --dce-reach-from=TakesAddr  before:  0 bodies, PXXAlloc no   <- the false NO
                                after:  37 bodies, PXXAlloc YES
                                        Allocs  [via @proc taken]

**The five-body table is unchanged by it — `PlainOnly` still 1/`no`** — which
is what says the new edge fires on the address and not on everything. Without
that row, "the false NO became a YES" and "the walk now reaches everything from
everywhere" are the same observation.

Each category is now named separately in the summary line. An earlier version
folded the `@proc` rows into the unowned-code count and printed *"37 only via
unowned code"* for a set that was 36 + 1 — a summary contradicting the rows
above it, caught before it landed.

**STILL OPEN, AND IT IS WHY A `NO` IS STILL NOT A SAFETY CLAIM:** a body
reached through a VMT/RTTI dispatch slot. `MethodFixups` has **no owning
body** — a vtable slot is DATA, written at image-write time — so there is no
site to attribute and no edge to add. That is a different shape from `@proc`
and this does not touch it. 8e's live instance is the control when it is built:
`bug-nilpy-a-python-override-of-a-virtual-pascal-method-segfaults-...`.
