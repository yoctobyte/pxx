---
track: N
prio: 60
type: feature
owner: frankh-c0
blocked-by: []
status: working
created: 2026-09-20
found-by: frankb-8e
summary: "SPLIT OUT OF feature-n-a-nilpy-def-has-no-native-abi-entry-point-to-hand-to-a-c-callback 2026-09-20 BECAUSE THAT TICKET'S ACCEPTANCE CRITERION WAS UNSATISFIABLE BY IT: it read `the ESP demo stops polling`, while its own `What this does NOT deliver` section says delivering it cannot achieve that. A gate that cannot pass is not a gate, so the bar moved here and that ticket's acceptance was restated to what it does deliver. THE MECHANISM, WHICH IS WHY THIS IS NOT MORE OF THE SAME WORK: the delivered thunk `$pycbthunk_<def>_<sig>` marshals through Variants, and BOXING A VARIANT ALLOCATES. An ISR that allocates is a latent crash with GOOD LATENCY NUMBERS -- it does not fail on the bench, it fails when the heap lock happens to be held by the code the interrupt preempted, which is a schedule-dependent deadlock or corruption that a demo will not reproduce and a soak test might not either. So the existing thunk shape must NOT simply be pointed at an ISR slot. What is wanted is a RESTRICTED thunk: fixed arity, scalar-only parameters, no Variant anywhere on the path, provably allocation-free. THE ACCEPTANCE IS A PROOF OF ABSENCE, NOT A PASSING DEMO, and that is the hard part: `examples/esp32/nilpy-hw-c3` polling less is not evidence, because an allocating ISR usually works. The claim has to be that the emitted thunk contains no call that can reach the allocator, which is a property of the generated code and should be asserted against it rather than against behaviour. Pascal-side `interrupt;`/`iram;` already exist and are DONE (feature-esp32-isr-iram, 2026-06-21) -- this is the NilPy-side entry point, not that. Nothing measured yet: no repro, no emitted-code inspection, no allocation census of the current thunk. THE OWNER CALLED ESP INTERRUPTS A MUST-HAVE (relayed secondhand 2026-09-20, marked as such), which is why the parent sits at 85; this half is 60 because it is the harder and less specified of the two and nothing downstream is blocked on it today."
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
