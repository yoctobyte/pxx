---
track: A
prio: 60
type: feature
blocked-by: []
---

# Float exception mask control (SetExceptionMask-style, FPC emulation opt-in)

- **Type:** feature (runtime / math) — Track A
- **Status:** working
- **Opened:** 2026-07-02, from the math-error design discussion with the user.

## Decision already made (user, 2026-07-02)

- **Default stays quiet IEEE**: `1.0/0.0 = +inf`, overflow → inf, invalid →
  NaN, silently propagated. Rationale (user): real-world measurement/streaming
  data with out-of-bounds inputs is better served by inf/NaN propagation
  through complex math than by aborting mid-computation; FPC's
  unmask-by-default is the wrong default for that domain.
- **FPC emulation is opt-in**: we want to be *able* to emulate FPC closely
  (FPC unmasks x87 CW / SSE MXCSR at startup, so float div-zero = RE 208 /
  EZeroDivide, overflow = RE 205, invalid = RE 207), but behind an explicit
  runtime/compile opt-in, not the default.

## Scope

- `GetExceptionMask` / `SetExceptionMask([exZeroDivide, exOverflow, ...])`
  API (FPC Math-unit-compatible surface) manipulating MXCSR (x86-64) /
  FPCR (aarch64) / per-target equivalent.
- Unmasked exception → hardware SIGFPE → signal handler (the blocker) decodes
  siginfo `si_code` (FPE_FLTDIV/FPE_FLTOVF/FPE_FLTUND/FPE_FLTINV) → FPC-style
  runtime error 205/206/207/208, hook-upgradable to a raised exception like
  the integer path's PXXDivZeroHook.
- Possibly a `--fpc-float-errors` CLI flag / directive that unmasks at entry
  (the "emulate FPC closely" switch).
- Note: pre-instruction value checks are NOT a substitute here (user + design
  discussion): a zero-divisor test misses overflow (`1e308/1e-308`) and
  denormal cases; the mask/trap mechanism is the only honest implementation.

## Acceptance

Default behavior unchanged (quiet inf/NaN — add a pin test for that too);
with the mask cleared, float div-zero/overflow/invalid produce the documented
runtime errors; mask round-trips via Get/SetExceptionMask; x86-64 first.

## BLOCKED on SA_SIGINFO — measured 2026-08-13

Recording the dependency the ticket did not have. The acceptance criterion is
that an unmasked float exception produces the *documented* runtime error —
205 (overflow) / 206 / 207 (invalid) / 208 (div-zero), i.e. **distinguished by
cause**. The handler must therefore learn WHICH exception fired, and today it
cannot:

- the x86-64 signal runtime (`EmitSignalRuntime`, ir_codegen.inc) installs the
  dispatch stub with the **plain** handler ABI — `edi` = signal number and
  nothing else. No `SA_SIGINFO`, so no `siginfo_t`, so no `si_code`.
- **the MXCSR status flags are NOT an alternative.** That was the promising
  route (read the sticky IE/ZE/OE bits in the handler and skip siginfo
  entirely), so it was measured rather than assumed:

  ```
  1.0/0.0     si_code=FLTDIV   mxcsr_flags=0x00
  0.0/0.0     si_code=FLTINV   mxcsr_flags=0x00
  1e308*10    si_code=FLTOVF   mxcsr_flags=0x00
  ```

  Linux hands the signal handler a CLEAN FP state, so the status flags read
  0x00 no matter which exception trapped. `si_code` is the only carrier.
  (Same probe also shows why a handler that `siglongjmp`s out never re-traps:
  skipping `sigreturn` leaves the handler's own masked MXCSR installed.)

So `feature-signal-siginfo-ucontext` item 1 (SA_SIGINFO + ucontext) is a hard
prerequisite, not a nice-to-have. That ticket already lists this one as a
consumer; the edge is now recorded in both directions, so prio 60 propagates
down to it.

**What is NOT blocked**, if this is picked up before siginfo lands: the
`Get`/`SetExceptionMask` API itself (MXCSR on x86-64 / FPCR on aarch64) and
the "default stays quiet IEEE" pin test are self-contained. Deliberately NOT
landed as a half-slice — an exception-mask API whose unmasked path produces an
undifferentiated crash is the consolation microfix
`devdocs/dev/root-cause-over-microfix.md` warns about, and the mask is only
worth having once the trap means something.

**Un-blocking checklist (both switches):** when siginfo lands, move this file
OUT of `blocked/` *and* clear the `blocked-by:` line. Either one alone leaves it
invisible to `ready`/`next`.

**UNBLOCKED 2026-08-13** — both switches thrown (this file moved to `backlog/`,
`blocked-by:` emptied). The prerequisite is met and then some: SA_SIGINFO is set
and `si_code` readable via `__pxxSigCode` on ALL FIVE hosted Linux targets, not
just x86-64 (`feature-signal-siginfo-ucontext` slices 1 and 2). Note
`__pxxSigCode` is typed **Integer**, not Int64 — si_code's real width, retyped
so the ILP32 targets need no sign word.

That parent ticket stays OPEN, but for work this one does not need: the
fault-to-catchable-raise PC rewrite, threadsafe masks, sigaltstack, the
FPC-compat `Signal()` surface, SIGPIPE policy. Do not re-block on it.
