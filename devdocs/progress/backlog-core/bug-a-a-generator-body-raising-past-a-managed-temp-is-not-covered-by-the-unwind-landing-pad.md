---
slug: bug-a-a-generator-body-raising-past-a-managed-temp-is-not-covered-by-the-unwind-landing-pad
track: A
prio: 35
type: bug
status: open
blocked-by: []
found: 2026-09-02
found-by: frankC
owner: ""
tags: [memory-leak, exceptions, unwind, generators]
summary: "UNMEASURED RESIDUAL, filed so it has an owner rather than living in a closed ticket's scope note. bug-a-a-managed-temp-in-a-frame-unwound-by-an-exception-is-never-released was fixed by asking the landing-pad gate a second time inside CompileAST, but the request is raised ONLY for a plain body: an asm body and a generator/stackless body keep the prologue decision. So a generator whose step function raises past a hidden managed argument temp should still leak one block per raise. Should -- not does: a standalone repro was attempted and did not get past a parse error unrelated to the bug, so this is reasoned from the code path and NOT measured. Verify before working it; if it does not reproduce, close as rejected rather than leaving it open at a guess."
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
