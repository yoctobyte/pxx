---
track: A
prio: 55
type: refactor
blocked-by: []
status: done
tags: [cross-target, wasm32, managed-locals, root-cause]
summary: "One concept — release a frame's managed locals at scope exit — is implemented seven times: symtab.inc EmitManagedLocalCleanup (x86-64), five hand-written arms in ir_codegen.inc (i386/arm32/aarch64/xtensa/riscv32), and WasmEmitManagedLocals in ir_codegen_wasm32.inc. Measured 2026-09-06: the five register arms are decision-for-decision identical and the wasm32 copy was missing a whole row (fixed, d58828d8c) and still consults neither skip predicate. CLAUDE.md's rule is that three mechanisms for one concept is a design flaw; this is seven, and the copy that drifts is never the one anyone measures."
---

# The scope-exit managed-local release loop has seven copies

## The census, measured not asserted

`EmitManagedLocalCleanupForTarget` (ir_codegen.inc:13943) dispatches on
`TargetArch`. Extracting each arm's decision chain and the helpers it calls:

| copy | where | lines |
| --- | --- | --- |
| x86-64 | delegates to `EmitManagedLocalCleanup`, symtab.inc:14023 | 234 |
| i386 | ir_codegen.inc arm | 195 |
| arm32 | ir_codegen.inc arm | 197 |
| aarch64 | ir_codegen.inc arm | 170 |
| xtensa | ir_codegen.inc arm | 176 |
| riscv32 | ir_codegen.inc arm | 206 |
| wasm32 | `WasmEmitManagedLocals`, ir_codegen_wasm32.inc:6737 | 196 |

The five register arms emit the same nine helpers in the same order —
`PXXIntfRelease PXXArrayReleaseImmediate PXXStrDecRef PXXVarClear PXXObjRelease
PXXPromoClear PXXRecordReleaseIntf PXXRecordRelease PXXDynArrayRelease` — and
carry the same decision chain, i386 differing only in hoisting `Kind = skLocal`
out of the loop. So today the five are IN SYNC. That is the finding, not the
absolution: they are in sync because people keep re-syncing them by hand, and
each re-sync is a chance to miss one.

## What being out of sync already cost

- **wasm32 had no `tyClass` arm at all.** Every NilPy object bound to a local
  leaked once per call, on that target only — measured `live` 1900 at N=2000
  and 7815 at N=8000 against a flat `live=1` on x86-64 for the same source.
  Fixed d58828d8c, guarded 223127f86.
- **wasm32 consults neither `SymSkipScopeExitRelease` nor
  `StacklessPersistentSlotSym`**, which the six others do. Still open —
  [[bug-a-the-wasm32-scope-exit-release-loop-consults-neither-skip-predicate]].
- The i386/arm32 static-array arm once released **element zero only** while
  riscv32 skipped the case entirely; both are recorded in the i386 arm's own
  comment. Three copies, three different behaviours, one concept.
- `SymSkipScopeExitRelease`'s own comment gives the reason it merges two
  unrelated ownership questions into one predicate: *"the emitters have six
  copies of this loop and the second copy is the one that stays broken."*
  Someone already hit this wall from the other side and worked around it.

## The shape of the fix

The per-target part of this loop is small: how to load a slot address, how to
load a slot value, how to call a helper. Everything else — walking `Syms[]` from
`Procs[CurProc].ScopeBase`, applying the skip predicates, classifying a symbol
into one of nine release kinds, choosing the helper and its argument shape — is
target-independent and is what is duplicated seven times.

So: one shared walker that yields `(symbol, helper name, argument kind)`, and a
per-target emitter with three entry points. `EmitZeroFrameSlot` and
`ManagedLocalZeroBytes` are the precedent — the zero-init half of this same pass
already asks a shared table, which is exactly why the zero half did not drift
while the release half did.

This is the case `root-cause-over-microfix.md` describes as the overhaul being
the SMALLER job: it deletes six copies of a nine-way classification.

## The trap, before anyone starts — RESOLVED, and left here because the
## resolution is the useful part

**This section said, until 2026-09-07, that "the wasm32 copy differs from the
other six in a way nobody has named yet" and told the next reader to name it
before normalising it away. That is no longer true and the correction matters
more than the warning did**, because a stale trap misroutes exactly the person
who takes the warning seriously.

What it was: frankwasm applied the correct predicate at the correct
granularity, in the shape the six right arms use, and reported REGRESSING two
passing generator rows (`0819a7f5f`). Two explanations were offered and both
were refuted, which is what made the residual look like an unnamed structural
difference.

What it actually was: **there was no regression.** frankwasm retracted the
causal half themselves (`7dd75f85a`) — the loop has no symbol to iterate for
that program, so the patch was a no-op there, and the likeliest cause of the
reading was a stale binary. The predicate landed (`8157808b2`), wasm32
consults `SymSkipScopeExitRelease` today at `ir_codegen_wasm32.inc:6942`, and
the ticket that carried all of this is `done`:
[[bug-a-the-wasm32-scope-exit-release-loop-consults-neither-skip-predicate]].

**The reusable part is the control, not the bug.** `yield 1; yield 2` was the
positive control in circulation for this whole episode and it is INERT: the
emitted module is byte-identical with and without the patch, and it prints
correctly on both targets in every configuration. So it could not have seen
the defect, could not have seen the fix, and could not have seen the
regression it was cited to demonstrate. A control that passes in every
configuration is not evidence about any of them. Use a shape that HOLDS A
MANAGED LOCAL ACROSS A YIELD — `test/wasm/check_nilpy_generator_slot.sh` is
that shape, and it asserts against the native oracle rather than a constant.

**The one difference that was real is now named and shared**, `55e7c31c2`:
wasm32 alone carried `not Syms[i].IsRef`. It is REDUNDANT, not merely
unreached — `IsRef` is True only on a symbol whose `Kind` is `skParam`
(enumerated across all eight assignment sites in the compiler), and all seven
loops already require `skLocal`. Removing it from wasm32 and adding it to all
seven were each byte-identical across every target. It now lives in
`SymSkipScopeExitRelease` with that enumeration beside it, because the
invariant it depends on is enforced nowhere and a double free is not a
diagnostic.

Coverage that already exists and will move if this does:
`test/wasm/check_scopeexit.sh`, `check_intf.sh`, `check_outparam.sh`,
`check_variantptr.sh`, `check_nilpy_objlocal.sh`. Note these are not enrolled in
a tier — [[feature-t-enrol-test-wasm32-in-a-tier-so-something-samples-the-backend]]
— so they are run by hand today.

## How it is being landed — one backend per commit

Not one diff. **Convert one copy to the shared helper at a time; each step is
independently correct, each is separately gateable, and the tree is shippable
between any two of them.**

The shared piece is `ScopeExitReleaseAction(i; var a1, a2, a3): Integer` in
symtab.inc, immediately above `EmitManagedLocalCleanup`. It answers the nine-way
classification and NOTHING else — it returns an `SXR_*` code (defs.inc) plus up
to three already-computed operands, and emits no bytes. The emission stays
per-target, because that part genuinely is per-target: how to load a slot
address, how to push an argument, how to call.

| step | copy | commit |
| --- | --- | --- |
| 1 | x86-64 (`EmitManagedLocalCleanup`, symtab.inc) + the SXR constants | `491035cfe` |
| 2 | i386 | this one |
| 3..6 | arm32, aarch64, xtensa, riscv32 | pending |
| 7 | wasm32 | pending — see the open difference below |

**The control at each step is a byte-identical A/B**, not a green: the previous
step's compiler and this step's compiler compile the same corpus for all seven
targets, and every object must `cmp` equal. A refactor that changes one emitted
byte is not this refactor. The corpus is the string/interface/record/class/
variant/array tests plus `compiler.pas` itself, and the harness asserts the
artefact EXISTS before comparing — a `cmp` of two files that were never built
reports identical and means nothing.

Two things the A/B cannot see, so both are run beside it:

- **A leak passes every value assertion, by construction.** The releases could
  vanish entirely and the corpus would still print the right answers. So
  `tools/assert_no_leak.sh` runs a program holding a local of every class the
  chain distinguishes: `allocs=31686 frees=31680 live=6` against a bound of 200,
  and the same numbers from the previous step's compiler.
- **The self-host fixedpoint proves nothing about a construct `compiler.pas`
  never writes**, which is every non-Pascal frontend. So a one-line probe from
  each — `x = "a" * 3` and its C, Rust and Zig equivalents — is compiled and RUN
  at each step. It costs under a second and it is the only thing here that
  would have caught a marshalling change.

## The one difference that must NOT be normalised away

wasm32's loop carries `not Syms[i].IsRef`; the other six do not. That is a real
divergence between the seven copies and step 7 must NAME it before it either
keeps or drops it — the trap section above is exactly this, and the refactor is
the moment the difference becomes invisible.

The classifier's own comment carries the reason it exists as code and not as a
convention: **a distinction that only exists in prose gets violated by the next
writer.** That is the whole argument for this ticket. Seven copies stayed in
sync by hand for as long as someone kept re-syncing them, and the copy that
drifted — wasm32, missing an entire arm — is the one nobody was measuring.

## Resolution — all seven copies are one classification

Landed one backend per commit, as the plan above required. Every step is an
ancestor of origin/master, verified with `merge-base --is-ancestor`:

| step | copy | commit |
| --- | --- | --- |
| 1 | x86-64 + the SXR constants | `491035cfe` |
| 2 | i386 | `8f61a1974` |
| 3 | arm32 | `e8d8ad082` |
| 4 | aarch64 | `736a3177a` |
| 5 | xtensa | `925e80f1e` |
| 6 | riscv32 | `6e5bed1ab` |
| 7a | the by-ref skip, asked once | `55e7c31c2` |
| 7b | wasm32 | `687701433` |

`EmitManagedLocalCleanupForTarget` now dispatches emission per target and asks
`ScopeExitReleaseAction` for the classification. Seven decision chains became
one; the emission stayed per-target, which is the part that genuinely is.

### DID THE OTHER SIX GAIN A SKIP THEY DID NOT HAVE? No — and it is structural, not just measured

Asked by frankA, and it is the right question to ask of a behaviour change
wearing a refactor's commit verb. wasm32 carried `not Syms[i].IsRef` and the
other six did not, so step 7a either names that difference or normalises it away
by accident.

**The answer is that the term was REDUNDANT, not merely unreached.** `IsRef` is
True only on a symbol whose `Kind` is `skParam` — eight assignment sites in the
whole compiler, enumerated in `55e7c31c2`, five of them setting False. Every one
of the seven loops already requires `Kind = skLocal`, which excludes `skParam`.
So the guard could not fire on any target, before or after.

Both directions were measured and both are byte-identical:

```
removing it from wasm32   95 identical, 0 differ
adding it to all seven    0 differ — x86_64 54, i386 51, arm32 51,
                          aarch64 51, riscv32 54, xtensa 53, wasm32 95
```

Deleting it would have been byte-identical too, and that is not what was done:
the invariant it rests on is enforced NOWHERE, so if a frontend ever gives a
local a borrowed slot, six of seven backends would release storage they do not
own — silently, because a double free is not a diagnostic. One predicate to
change beats seven to remember, which is this ticket's whole argument.

### The control, at every step

A **byte-identical A/B**, not a green: the previous step's compiler and this
step's compiler compile the same corpus for all seven targets and every object
must `cmp` equal. Final tally across the group: `identical=314 differs=0
both-refused=113`. The harness asserts the artefact EXISTS before comparing,
because a `cmp` of two files that were never built reports identical and means
nothing.

Two things that A/B cannot see, run beside it:

- **`tools/assert_no_leak.sh`**, because a leak passes every value assertion by
  construction — the releases could vanish entirely and the corpus would still
  print correct answers. `allocs=31686 frees=31680 live=6` against a bound of
  200, identical at every step.
- **A one-line probe from each frontend the quick tier does not cover** — NilPy,
  C, Rust, Zig — because the self-host fixedpoint proves nothing about a
  construct `compiler.pas` never writes. Under a second each, and the only thing
  here that would have caught a marshalling change.

### What it enabled, and what it cost

The thunk (`50e25f5f0`, `3d7cde305`) is only writable because the classification
is one function: `ManagedSweepSlotCount` asks `ScopeExitReleaseAction` the same
question the emitter asks, so the count cannot drift from what is emitted.
Against the seven-copy code it would have been an eighth copy of the skip logic.
That is **-31.9%** off the compiler's own artefact and **-2.04%/-2.51%**
wall-clock (`89a218380`, frank-subcoord).

One thing this did NOT establish, recorded because a later reader will want it:
`e86101766` measured that the sweep **cannot** skip unnamed temps. ~98% of swept
slots are compiler-minted temps, so that was the attractive optimisation, and it
is unsafe — `:13838`'s "does not outlive the statement" is about the temp's
VALUE, while the release loop needs a claim about OWNERSHIP of what it
references.

### No tstate verdict covers this

Breadth is down: seventeen `infra … no report (rc=1)` rows on seven in the last
sixty commits, against zero in the 177 before that. So no cross-target verdict
has seen any of these shas, and the byte-identical A/B plus the per-frontend
probes are the whole of the evidence rather than a supplement to a tier run.
Said explicitly because a reader would otherwise assume T covered it.

## Log
- 2026-09-07 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
