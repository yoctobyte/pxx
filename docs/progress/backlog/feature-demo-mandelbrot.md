# Demo — zoomable Mandelbrot explorer

- **Type:** feature
- **Track:** B
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-22
- **Relation:** Visual compute demo. Optional pressure on `lib/rtl/math.pas`;
  likely pressure on native inline assembler / hand-tuned kernels.

## Goal

Build a zoomable Mandelbrot explorer under `examples/mandelbrot/`, without
OpenGL. Start with native hosted output through the existing PCL/custom drawing
or bitmap-rendering stack, and keep the render kernel isolated so it can be
implemented in multiple ways:

- portable Pascal floating-point kernel;
- optional fixed-point/integer kernel that avoids most math-library dependency;
- optimized native x86-64 assembler kernel as the first hand-tuned backend.

## Scope

- Window or terminal/image view with pan and zoom controls.
- Deterministic color palette and iteration limit controls.
- CPU renderer only; no OpenGL/GPU dependency yet.
- Tiled or progressive redraw so zooming remains responsive enough to inspect.
- Kernel abstraction for selecting Pascal scalar vs native asm implementation.
- Benchmark output for render time / pixels per second / iterations per second.

## Math-library note

Mandelbrot itself mostly needs addition, multiplication, comparison, and integer
loop control. A floating-point implementation may still rely on the compiler's
float runtime, but it should not require transcendental functions. A fixed-point
or native-asm kernel may avoid `math.pas` entirely.

The native asm path is part of the feature, not a later rewrite: begin with
x86-64 because it is the Track B host baseline. Other targets can use the
portable Pascal kernel until their asm surfaces are mature enough.

## Coverage

- Floating-point or fixed-point arithmetic in hot loops.
- Large nested loops, palette mapping, and image buffer writes.
- Keyboard/mouse controls for pan/zoom/reset.
- Resize-triggered viewport recalculation.
- Optional native inline asm in an application-level hot path.
- Performance comparison between portable and optimized kernels.

## Acceptance

- `examples/mandelbrot/` contains a usable zoomable Mandelbrot application.
- It compiles with `$(PXX_STABLE)` and does not require OpenGL.
- A deterministic smoke mode renders a small viewport and checks a stable hash
  or selected golden pixels.
- Native x86-64 asm kernel exists behind an explicit mode or compile define, or
  a focused follow-up ticket records the exact missing asm/compiler capability.
- Any math/runtime/compiler gaps found while keeping the source platonic are
  filed as separate tickets.

## Log

- 2026-06-22 — Opened on user request: zoomable Mandelbrot application, no
  OpenGL yet, with optional math-library dependency and an expected native
  assembler optimization path starting on the host platform.
- 2026-06-22 — **Partial (Track B):** static ASCII render + deterministic
  smoke-mode landed — `examples/mandelbrot/mandelbrot.pas`: portable Pascal Double
  kernel (escape-time), 70x32 grid over the canonical window, and the acceptance
  "deterministic smoke mode + stable hash" via an integer escape-count CHECKSUM
  (3745966 on x86-64, FPC-confirmed). Wired into `make lib-test` + `make demos`.
  Doubles as the strict float cross-target probe (see
  feature-real-cross-target-consistency) — the checksum must match on every target
  (strict IEEE-754 Double is deterministic; a mismatch is a bug).
  **Still open** (keeps this in backlog): interactive pan/zoom explorer, the
  kernel-abstraction (fixed-point + native x86-64 asm kernels), and perf/benchmark
  output. Gap found + filed: bug-untyped-float-const (untyped + negative float
  consts rejected; worked around with locals).
