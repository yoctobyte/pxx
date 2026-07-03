# Register-based internal calling convention (args in registers, not stack slots)

- **Type:** feature (codegen — ABI-wide) — Track A
- **Status:** backlog
- **Opened:** 2026-07-03 (pin-time optimization campaign)
- **Umbrella:** the -O2 tier of [[feature-optimization-levels]]; split out
  because it is ABI-WIDE (every call site + every prologue must flip
  together) rather than a local pass.

## Motivation

PXX's internal convention on x86-64 today: every argument is pushed to the
stack, popped into rdi/rsi/... just before the call, and the callee's
prologue immediately SPILLS every register argument back into frame slots.
Each argument round-trips memory twice; the callee then reloads from the
frame on every use. FPC's register convention + register allocator is a big
chunk of the measured 2.04x generated-code gap (benchmark-compiler-runtime,
2026-07-03: FPC-built pascal26 compiles the compiler in 5.1s vs self-built
10.4s, identical source).

## Shape

- Keep the EXTERNAL SysV convention for cdecl/external as-is.
- Internal calls: first N integer/pointer args stay in registers end-to-end;
  the callee spills ONLY args whose address is taken (var-param source,
  @-taken, or referenced by nested/lifted routines) or that live across a
  call.
- This is a whole-program flag-day per target: land behind `-O2` (or a
  dedicated `--regcall`) so -O0 keeps the byte-identical debuggable model.
  Self-host gate becomes: pxx(-O0) byte-identical as today; pxx(-O2) built
  compiler passes full make test and fixedpoints against itself.
- Do x86-64 first (host, biggest pin-time payoff); cross targets follow the
  same IR-level liveness info later.

## Prerequisites

- Simple per-routine liveness/addr-taken analysis over the IR (also feeds
  [[feature-inline-routines]] eligibility and future register allocation).
- The -O flag plumbing from [[feature-optimization-levels]].

## Acceptance

Self-compile wall time drops measurably with -O2 (record in
benchmark-compiler-runtime); full make test green under a -O2-built
compiler; -O0 self-host byte-identical unchanged.
