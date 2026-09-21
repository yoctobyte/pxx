---
prio: 55
track: A
summary: "A compiler-emitted runtime stub that compiler.pas never causes to be emitted is invisible to the self-host fixedpoint AND to gate.sh quick, and the blindness is structural rather than a coverage gap to be topped up: the fixedpoint's discriminating power is exactly the set of constructs the compiler writes about itself, and --threadsafe is not one of them. Demonstrated with a dated casualty rather than argued -- 12d6c86f0 fixed a p70 heap-corruption regression (a signal handler granted the heap lock on a bare tid match, then allocating inside a half-updated heap) that had shipped for three days while the BROKEN and the FIXED compiler both printed 'converged after 1 round(s)'. The condition that springs it is any codegen whose output compiler.pas does not itself contain: the heap-lock stubs, the signal runtime, the div0 stub, the float-error hook, anything behind --threadsafe / --fpc-float-errors / --no-signals. Wants a deterministic BYTES-level assertion in a cheap tier, not another race-dependent runtime test -- the existing test_threadsafe_heap_lock_deadlock_diag does catch this defect but only by winning a race, which is what made it read as a flake for three days."
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

**This is not "add more tests".** The affected surface is enumerable and small:
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
