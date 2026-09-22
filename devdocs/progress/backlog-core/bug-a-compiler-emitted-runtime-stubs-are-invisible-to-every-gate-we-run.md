---
prio: 55
track: A
summary: "A compiler-emitted runtime stub that compiler.pas never causes to be emitted is invisible to the self-host fixedpoint AND to gate.sh quick, and the blindness is structural rather than a coverage gap to be topped up: the fixedpoint's discriminating power is exactly the set of constructs the compiler writes about itself, and --threadsafe is not one of them. Demonstrated with a dated casualty rather than argued -- 12d6c86f0 fixed a p70 heap-corruption regression (a signal handler granted the heap lock on a bare tid match, then allocating inside a half-updated heap) that had shipped for three days while the BROKEN and the FIXED compiler both printed 'converged after 1 round(s)'. The condition that springs it is any codegen whose output compiler.pas does not itself contain: the heap-lock stubs, the signal runtime, the div0 stub, the float-error hook, anything behind --threadsafe / --fpc-float-errors / --no-signals. THIS IS THE PROBE RULE, NOT A CASE FOR A WIDER GATE -- a valid pin is the fixedpoint and nothing else may block one; CLAUDE.md's existing remedy, 'carry a one-line probe in the affected shape', was simply never applied here, and a --threadsafe canary is a PROBE that blocks nothing. Wants a deterministic BYTES-level assertion rather than another race-dependent runtime test -- the existing test_threadsafe_heap_lock_deadlock_diag does catch this defect but only by winning a race, which is what made it read as a flake for three days."
---

## The claim, and what would retire it

`make compiler/pascal26` is the one row CLAUDE.md says GATES a pin ("a row that
restates the pin's own DEFINITION gates; every row that reports a property of
the TREE grades"). That is correct and this ticket does not dispute it. The
point is narrower: **for one defect class its answer is an identity, not
evidence** — it reads the same whether the code under test is right or wrong.

Measured 2026-09-21 while fixing `12d6c86f0`:

| tree | fixedpoint | the emitted async-re-entry refusal |
| --- | --- | --- |
| broken (`ce18a30c8`) | `converged after 1 round(s)` | **absent** |
| fixed (`12d6c86f0`) | `converged after 1 round(s)` | present |

`compiler.pas` is not built `--threadsafe`, so it never causes
`EmitHeapLockStubs` to run. CLAUDE.md already states the general principle — the
fixedpoint "cannot see a construct the compiler never writes". What is new here
is the severity and a date: the invisible construct was live heap corruption at
p70, and `gate.sh quick` did not see it either.

**This is not "widen the gate", and it is not "add more tests".** A valid pin
is the self-host fixedpoint; nothing else may block one, and this ticket asks
for nothing that blocks. What it asks for is the probe CLAUDE.md already
prescribes for exactly this case. The affected surface is enumerable and small:
codegen reachable only under a flag `compiler.pas` is not built with —
`--threadsafe` (the heap-lock stubs and the reentrant layer), the signal
runtime, `--fpc-float-errors`, `--no-signals`, and the per-arch stub emitters
for targets the self-host does not exercise.

## Why a runtime test is the wrong instrument here

`test/test_threadsafe_heap_lock_deadlock_diag.pas` DOES catch this defect. It
caught it for three days and was read as a flake, because it catches it by
winning a race: a passing run is ~4.5 s and a failing one hangs to the harness
timeout, with nothing in between. Race-dependent evidence is what let the
regression sit.

The instrument that actually settled it was **the emitted bytes** — the grant
path read `cmp [owner],rsi / jne .acquire / jmp .bump` with nothing between
them. That is deterministic, costs one compile, and cannot flake.

Note the trap for whoever writes the assertion: there IS a bounds test in the
broken binary (the TLS tid-safety check at a nearby address), so an assertion
that greps for "a bounds compare" **passes on the broken build**. Assert the
specific pair against `BSS_SIG_ALTSTK`/`_ALTSS`, or assert the refusal's target.

## Already done, and why it is not enough

`12d6c86f0` adds a build-time guard that refuses when `BSS_SIG_ALTSTK` is
unallocated at prologue time, positive-controlled by deleting the call it
depends on and confirming the refusal fires and emits no binary. That closes
**this** slot. It does nothing for the next stub whose dependency moves.

## Open question for whoever takes it

Whether the cheap form is a bytes assertion per stub, or one fixture compiled
under each such flag whose output is diffed against a checked-in disassembly of
the interesting region. The second scales but pins addresses, which move.

## 2026-09-22 (frankh-c0) — TWO NEW DATED CASUALTIES, and a different KIND of casualty from the one this ticket has

Found by promoting `--dce` to the default `-O2` and running a full tier. Both
are on this ticket's own springing list, by name, in its summary.

| flag | expected | got under `--dce` | under `--no-dce` |
| --- | --- | --- | --- |
| `--fpc-float-errors`, division by zero | `208` | **139 (raw SIGSEGV)** | `208` |
| `--fpc-mem-errors`, nil read | `216` | **139 (raw SIGSEGV)** | `216` |

`test-core#519` and `test-core#2353` in the 2026-09-22 full tier.

**THE MECHANISM IS NOT THIS TICKET'S AND I FIRST WROTE THAT IT WAS.** My first
draft of this section said *"a handler reached only by being INSTALLED has
nothing in the call graph pointing at it"* — plausible, this ticket's own
shape, and **refuted by a two-sided control frankb-8e ran and I reproduced**:
if that were the cause, every installed-only handler would break, and
`test_signal_handler_callback_b336` and `test_setsignalhandler_call` both come
out **rc=0 under `--dce`**. Only the sites with a droppable body between the
reference and its target break.

The real mechanism is `EmitCodeAbsToRdx` (`ir_codegen.inc:1001`): it
materialises a code address as `call +0 / pop rdx / add rdx, imm32` where
`imm32 = targetOff - CodeLen` is **a delta fixed at emit time**, and it records
no `CodeRef` — so the pass neither protects the range nor re-aims the delta.
Three of its seven call sites sit adjacent to their targets and survive; the
`--fpc-float-errors` ones do not. A third spelling of "reference a code
offset", beside the `EmitCallProc` and `IREmitCodeCall` that `dce.inc:24-29`
enumerates.

**So these two rows belong here as casualties of the GATE BLINDNESS — which is
this ticket's actual claim and is untouched — and NOT as instances of its
mechanism.** 8e's caution is the right one and I had already walked into it:
*do not let the slug stand in for the mechanism.* The slug was handed to me by
a third seat, it fit, and I wrote a mechanism to match it before anyone
measured one.

### The part worth more than the two rows: THE CASUALTY IS AN ARGUMENT, NOT A SHIPPED BUG

This ticket's existing casualty is `12d6c86f0` — a heap-corruption regression
that shipped for three days while both compilers printed `converged after 1
round(s)`. **A shipped bug can always be read as somebody being careless**, which
is the weakest form of evidence for a claim about a STRUCTURAL blindness.

This one is the other kind. A seat spent a night promoting a pass, reported
four separate times that *"the self-host fixedpoint converges at the new
setting, which is the one row that GATES rather than grades"*, and was
**correct about that row every single time**. The row was green. It would have
been green if the pass dropped every handler in the tree. Nobody was careless
and the sentence was true; it was doing rhetorical work it cannot support.

**The transferable form, which is what this ticket is for:** the fixedpoint
being green says the compiler still reproduces itself under the new default. It
says nothing about whether the new default breaks the signal runtime. **A
gate's authority is scoped to what it can DISCRIMINATE, and the two claims are
indistinguishable while the row is green.**

So the promotion was refused by the TIER, and the tier is the only instrument
in this repo that could have refused it. That is this ticket's thesis with a
worked example attached.
