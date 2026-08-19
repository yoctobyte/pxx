---
track: A+F
prio: 30
type: feature
summary: "__pxx_fesetround/__pxx_fegetround exist and flip MXCSR, but only the C frontend can reach them, and off x86-64 they are an accepted no-op returning 0 — so Pascal cannot get a SetRoundMode that actually sets the mode"
---

# Expose the rounding-mode intrinsic to Pascal (and make it real off x86-64)

- **Type:** feature — Track A (`compiler/parser.inc` + the per-target stub in
  `compiler/cparser.inc`)
- **Opened:** 2026-08-09
- **Filed by:** Track B, finishing
  [[bug-b-rounding-api-gaps-setroundmode-roundto-lround]]. Three of that
  ticket's four items landed; this is the fourth, and it is not Track B's to
  write.

## What already exists

`compiler/cparser.inc` emits `__pxx_fesetround(mode)` / `__pxx_fegetround()` as
raw machine stubs, with the glibc x86 `FE_*` encoding (`TONEAREST=0`,
`DOWNWARD=0x400`, `UPWARD=0x800`, `TOWARDZERO=0xC00`). On x86-64 it flips the
**MXCSR RC bits [14:13]** (`= FE value << 3`) via `stmxcsr`/`ldmxcsr`. The
comment there records the reason it is sufficient: pxx does ALL double
arithmetic in SSE, so MXCSR is the only rounding state that matters — there is
no x87 use. `lib/crtl/include/fenv.h` exposes it to C, and quickjs's `js_dtoa`
already depends on it.

## The two gaps

1. **Pascal cannot reach it.** Nothing in `parser.inc` / `lexer.inc` knows the
   name, so `lib/rtl/math.pas` has no way to write the control word.
2. **Off x86-64 it is a lie waiting to happen.** Every other target — including
   i386 — takes `EmitCReturnZeroStub`: an accepted no-op returning 0. That is a
   defensible stance for C (hosted-x86-64 bring-up scope, same as `alloca`), but
   a Pascal `SetRoundMode(rmDown)` built on it would silently not change the
   mode on four of five targets. A mode-setter that does not set the mode is
   worse than a missing one, so Track B did not ship a wrapper over it.

## Why it is worth doing

`Round` is not an algorithm in Pascal, it is a float→int conversion in the
current hardware mode — which is exactly why our default is ties-to-even and
matches FPC. FPC exposes `SetRoundMode` and it demonstrably works there
(`rmDown` turns `0 2 2 4` into `0 1 2 3`). We match FPC's default but offer no
supported exit, and the user who is surprised by nearest-even has nowhere to go.

The ticket that filed this also notes the mode has teeth on the other targets:
arm32's `Round` lowers to `vcvtr.s32.f64`, which honours FPSCR RN — so making
the stub real there is writing a control register, not reimplementing rounding.

## Scope

- Expose `__pxx_fesetround` / `__pxx_fegetround` to the Pascal frontend.
- Implement them for real on the targets whose conversion honours a mode
  register (arm32/aarch64 FPSCR, i386 MXCSR — i386 uses SSE for doubles too),
  or keep the no-op ONLY where it is genuinely unimplementable and make that
  visible rather than silent.
- Track B then adds `TFPURoundingMode` / `SetRoundMode` / `GetRoundMode` to
  `lib/rtl/math.pas` on top, matching FPC's enum ordinals (measured:
  `rmNearest=0, rmDown=1, rmUp=2, rmTruncate=3`, default `rmNearest`).

## Gate

`make test` + self-host fixedpoint, plus a probe showing `Round` of a RUNTIME
value changing with the mode on each target that claims support — literal
arguments get constant-folded and appear mode-insensitive, which is how this
would otherwise pass while doing nothing.

<!-- float category -->
Indexed on [[meta-float-accuracy-policy]] — the standing float-accuracy index.
Collect, do not fix piecemeal; see the working rule there.

## Triage 2026-08-19 (Track D re-triage pass, pin v363)

**Genuine feature, still wanted, unchanged.** Measured: a Pascal program that
`uses math` and calls `SetRoundMode(rmDown)` fails with
`undefined variable (SetRoundMode)` — the entry point is still absent from
`lib/rtl/math.pas`, because the intrinsic it would need is still C-frontend
only. Gap 1 stands exactly as filed; nothing about gap 2 (the off-x86-64
no-op) is contradicted by this.
