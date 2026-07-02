# Float exception mask control (SetExceptionMask-style, FPC emulation opt-in)

- **Type:** feature (runtime / math) — Track A
- **Status:** backlog — **blocked on** [[feature-signal-handlers]]
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
