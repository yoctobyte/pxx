---
slug: bug-a-a-generator-body-raising-past-a-managed-temp-is-not-covered-by-the-unwind-landing-pad
track: A
prio: 35
type: bug
status: done
blocked-by: []
found: 2026-09-02
found-by: frankC
owner: frankb-78
tags: [memory-leak, exceptions, unwind, generators]
summary: "FIXED for the STACKLESS form, and the cause was not the gate: EmitManagedLocalCleanup opened `if CurProcIsStackless then Exit;`, so the whole cleanup -- epilogue AND landing pad -- was off for a stackless proc and a pad would have had nothing to emit. Right about the generator's live state, wrong about its hidden temps, which have no persistent slot and die inside one statement. Replaced both blanket exits with one per-symbol predicate (StacklessPersistentSlotSym). Temp leak 1.871 -> 0.936 per raise, and the no-raise row went from 0.986/iter to FLAT. Residual (the instance, on the unwind path) and the stackful form are filed separately."
---

# A generator raising past a managed temp is outside the landing-pad fix

## What is known

[[bug-a-a-managed-temp-in-a-frame-unwound-by-an-exception-is-never-released]]
closed the plain-body case: the gate is asked a second time in `CompileAST`,
between `IRLowerAST` and `IREmitMachineCode`, where the hidden argument temps
already exist.

`pasparser_proc.inc` raises that request only on the plain body path. The `asm`
and generator/stackless branches call `CompileAST` without it and keep the
prologue decision — the one that cannot see temps. A generator step function
that contains `raise Exception.Create(gmsg + Chr(65))` therefore has the same
shape the parent ticket measured at ~0.99 leaked blocks per raise.

**`asm` is deliberately excluded and is NOT part of this ticket**: an asm body
emits its own code and mints no temps through lowering.

## What is NOT known, and it is the whole ticket

**No measurement.** A standalone repro (`generator;` routine that yields once
then raises, driven by `for v in Gen(1)` inside a `try`) did not compile —
a parse error at the statement following the `for..in`, reproduced with the
stackful and stackless forms and with a `begin/end` body, and reproduced with
syntax copied verbatim from `test/test_for_bounds_before_control_var.pas`,
which itself compiles cleanly. So the failure is in the scratch program, not in
the compiler, and it blocked the measurement rather than revealing anything.

That parse friction is worth ten minutes to someone who knows the for-in
lowering; it is the only thing between this ticket and a number.

## What was ruled out

The parent fix does not BREAK generators: `test_for_bounds_before_control_var.pas`
(both generator lowerings) compiles byte-identically, 118552B, on the pre-fix
and post-fix compilers.

## Acceptance

- Either a census showing a per-raise slope for a generator body, and a fix
  extending the late gate to that path — or a measurement showing it does not
  leak, and this ticket moves to `rejected/`.
- If it does leak: the generator branch's frame interacts with CoSwitch, so
  raising the same request there is not obviously safe and needs its own
  argument, not a copy of the plain-body one.

## Measured, and the parse friction was the scratch program

frankC's repro did not compile and they said so — "the failure is in the scratch
program, not in the compiler". Correct. The working shape needs `uses coroutine,
slgen, sysutils;` for the stackless form (the compiler says so: *"the slgen unit
is not in scope"*), and then it builds first try.

**It reproduces.** `Once` = a `try` around `for x in Gen(1)`, `Gen` a
`generator; stackless;` that yields once then raises, N iterations,
`-dPXX_ALLOC_CENSUS`, live at the last threshold, slope as the measurement:

| raiser body | @2000 | @8000 | slope, before | slope, after |
| --- | --- | --- | --- | --- |
| `raise Create(gmsg)` — no temp | 1901 | 7815 | 0.986 | **0.986 — residual, see below** |
| `raise Create(gmsg + Chr(65))` — temp | 3608 | 14836 | **1.871** | **0.936** |
| `Length(gmsg + Chr(65)) = 0` — temp, no raise | 1901 | 7815 | 0.986 | **flat, live=2** |

## The cause was NOT the gate, and the first fix I wrote did nothing

The obvious reading — "the generator branch keeps the prologue decision, so arm
the late request there too" — is what the ticket suggested and what I did first.
**It changed nothing**: same census, and the emitted program was the same size,
so no pad was ever armed.

The discriminator that named the real cause: move the temp into a plain
procedure called FROM the generator body. Same allocs (5411 / 22253, so the same
temp is minted), and it does not leak — slope 0.936, the baseline. **So the temp
leaks only when it belongs to the step function's own frame.**

Which is because `EmitManagedLocalCleanup` opened `if CurProcIsStackless then
Exit;` — the whole cleanup, epilogue AND landing pad, is disabled for a stackless
proc. There was nothing for a pad to emit. The blanket exit is right about the
generator's LIVE STATE and wrong about everything else in the frame: a temp
minted during `IRLowerAST` of the step body has no persistent slot (it did not
exist when `AssignStacklessSlots` ran) and dies inside one statement.

## The fix — one predicate, replacing two blanket exits

`StacklessPersistentSlotSym(i)` = `CurProcIsStackless and SymGenSlot[i] >= 0`.
Slotted means live across a yield; unslotted means it is not. It is the answer
`AssignStacklessSlots` already computed, asked at the other end. Applied per
symbol on the cleanup loops of `EmitManagedLocalCleanup` (x86-64) and all five
arms of `EmitManagedLocalCleanupForTarget`, and — this is the part that makes
the pad appear at all — in `ProcHasManagedLocalCleanup`, which is the gate.
Both blanket exits are gone. The late request for the stackless branch stays:
it is necessary and was not sufficient.

**The third row going flat was not the target.** The blanket exit was leaking the
step function's temps on the ORDINARY return path too, and nobody had measured
that because the program that shows it has to build a temp inside a generator.

## The residual, which is a different leak and now has an owner

Row one — no temp anywhere — still leaks ~0.99 per raise. A plain non-generator
raise+catch is flat at live=2, and row three is flat, so it is neither the
exception object nor generators in general: it is the generator INSTANCE, whose
`SlFree` lives in the loop teardown that the unwind skips. Filed as
`bug-a-a-generator-instance-is-not-freed-when-an-exception-escapes-the-for-in`.
That is why the new test's bound is 3000 rather than 50, and the test says so.

**The STACKFUL form is UNCHECKED, not fine.** An exception raised inside a
`generator;` (coroutine) body does not reach the driving `for..in`'s handler at
all — the process dies with `Unhandled exception` where the identical stackless
source gives `caught=3`. That blocked the measurement rather than answering it,
and is filed as
`bug-a-an-exception-raised-in-a-stackful-generator-body-does-not-reach-the-for-in-handler`.
This ticket's own note that "the generator branch's frame interacts with
CoSwitch, so raising the same request there needs its own argument" stands, and
that argument cannot even be started until the stackful raise arrives somewhere.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
