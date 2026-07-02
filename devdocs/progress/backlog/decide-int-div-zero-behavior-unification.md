# DECIDE: unify integer div/mod-by-zero behavior across targets

- **Type:** decision (low priority) — Track A
- **Status:** backlog — parked by design; revisit when cross-target work or
  the signal/exception stack ([[feature-signal-handlers]]) matures.
- **Opened:** 2026-07-02, capturing the user design discussion so the eventual
  decision starts from the recorded trade-offs.

## Current state (after the x86-64 slice landed, v135)

| target | `i div 0` today |
|---|---|
| x86-64 | pre-divide check → `Runtime error 200`, exit 200 (`--no-div-check` restores raw SIGFPE) |
| i386 | raw SIGFPE core dump |
| arm32 / aarch64 | hardware yields **0**, silently (ARM spec) |
| riscv32 | hardware yields **-1** (all ones), silently (RISC-V spec) |
| xtensa | hardware divide traps; software divide (LX6) undefined-ish |

## Positions recorded (2026-07-02 discussion)

- **User**: "returning zero is a sane result" — perspective from real-time
  measurement data where inputs go out of bounds inside complex math;
  abort-on-math-error is a theorist's default, not a practitioner's. Ints are
  acknowledged as different from floats, and riscv's -1 is the real outlier
  (neither a sane value nor an error). Halting should at minimum be behind a
  compiler switch (that exists now: check is default-on, `--no-div-check`
  opts out — whether that polarity is right is part of this decision).
- **FPC parity** (we want to be able to emulate closely, defaults may differ):
  FPC checks unconditionally (no switch at all) → RE 200; with sysutils in the
  uses closure its initialization installs hooks converting RE→ raised
  `EDivByZero`. The PXXDivZeroHook in builtinheap mirrors exactly that design
  and is ready for a future exception-providing unit to install into.

## Options on the table

1. **RE 200 everywhere** (extend the pre-check to the other 5 backends, ~9
   sites incl the 64-bit soft-div helpers on 32-bit targets): FPC-parity,
   consistent, kills the ARM silent-0 / riscv -1 divergence.
2. **Defined result everywhere** (e.g. `x div 0 = 0` by decree, check emits a
   cmov/select instead of a call): user's "sane result" position; cheap;
   diverges from FPC unless behind the emulation switch.
3. **Switchable semantics**: `--div-zero=error|zero|trap` (or directive) —
   both camps served; more surface to test per target.
4. **Catchable exception**: needs an exception-class home that is not
   sysutils (user: prefer builtins) — i.e. move/define a minimal
   Exception/EDivByZero in builtin, or wait for
   [[feature-emission-size-dce]] so carrying it is free. Hook mechanism
   already in place either way.

## Also unguarded today (fold into whichever option wins)

- `Low(Int64) div -1` / `mod -1`: x86 idiv still SIGFPEs (overflow trap, not
  zero divisor). FPC raises RE 215 (overflow). Either a second compare in the
  check or the signal handler catches it.

## Acceptance (of the decision, not code)

A written choice among the options (or a hybrid), with default + switch
polarity + FPC-emulation story fixed; implementation tickets then follow
per target.
