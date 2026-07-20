---
prio: 40
track: B
---

# Demo — real-time auto-zoom Mandelbrot with a per-target ASM iteration kernel

- **Type:** feature — flagship visual demo. Track B/E (app built with `$(PXX_STABLE)`;
  a compiler/asm gap it hits → file under the owning lane).
- **Opened:** 2026-07-17 (user request, during the parallel-processing work).
- **Relation:** the visual/animated sibling of `examples/mandelbrot/mandelbrot.pas`
  (integer + float kernels, checksum oracle) and `mandelbrot_parallel.pas`
  (parallel scanlines). Complements [[feature-demo-mandelbrot-gui-threaded]] (that
  one is the GTK/GL variant; this one is the animation + asm-kernel focus, TUI-first).
  Uses the now-shipped `parallel(P) for` / distribution policy
  ([[feature-parallel-for-scheduling-policy]]).

## Why this demo (and why FLOAT is fine here)
The existing Mandelbrots are deliberately portable (Double / Q4.28) — the point
there is a deterministic cross-target checksum. THIS demo is the opposite: it is
**allowed to be optimized**, because a real Mandelbrot's hot loop is a tiny
hand-written kernel. So it doubles as a **showcase of the inline-asm frontend**:
a small per-target asm iteration kernel (x86-64 SSE2, aarch64 NEON/VFP, i386 x87/
SSE, arm32 VFP) computes the escape count for a pixel (or a whole scanline),
called from the parallel scanline loop. That is honest — we advertise "you *can*
drop to asm where it matters", and this proves it — while the portable kernels
stay the correctness oracle.

## Goal (the "usual attractive stuff")
An interactive/animated Mandelbrot that looks good:
1. **Auto-zoom** — cycle through a handful of well-known deep-zoom target points
   (e.g. seahorse valley -0.743643887037, 0.131825904205; the classic
   -0.7436447860, 0.1318252536; a minibrot at -1.25066, 0.02012; Misiurewicz
   points), zooming in smoothly then out / cutting to the next. Precomputed path,
   no interaction required.
2. **Double-buffer + swap** — render the next frame into a back buffer while the
   front is shown; swap on completion (tear-free).
3. **Palette rotation** — cycle the colour LUT each frame for the shimmering-band
   look; cheap (LUT index offset), independent of the escape counts.
4. **Image rotation** — optional slow rotation of the sampling basis (rotate the
   complex-plane axes per frame) for extra motion.
5. **Parallel render** — `parallel(pdOnDemand) for row := ...` over scanlines (or
   tiles), each worker calling the asm kernel; on-demand distribution because deep
   zooms have very uneven per-row cost (in-set rows hit MAXIT).

## Surfaces (phase it)
- **Phase 1 — TUI (ANSI truecolor).** Reuse `ansiterm` (the existing mandelbrot's
  `RunTUI` already does truecolor bg blocks). Half-block / quarter-block glyphs for
  2x vertical resolution. Auto-zoom loop + palette rotation. Runs anywhere, no GUI
  deps. This is the deliverable to aim for first.
- **Phase 2 — GUI.** `lib/pcl` (gtk3 / glarea) framebuffer blit, higher res. Shares
  the kernel + zoom path with Phase 1. (Overlaps
  [[feature-demo-mandelbrot-gui-threaded]] — do one, reference the other.)

## The asm kernel (the interesting bit)
`function EscapeAsm(cre, cim: Double; maxit: Integer): Integer;` — one per target,
behind `{$ifdef CPU*}`, using the inline-asm frontend (`asm ... end`, or an
`.asm`-frontend unit). Kernel = the z:=z²+c escape loop in registers:
- x86-64: SSE2 scalar doubles (mulsd/addsd/subsd, ucomisd for the |z|²<=4 test).
- aarch64: VFP/NEON doubles (fmul/fadd/fcmp).
- i386: SSE2 if assumed, else x87.
- arm32: VFP.
Keep a portable Pascal fallback (`EscapeCountLimit`) for other targets and as the
correctness oracle: assert the asm kernel's escape counts equal the portable
kernel's over a test grid (same determinism discipline as the checksum) before
trusting it. A per-scanline kernel (compute a whole row in asm, amortize call
overhead) is a nice extension once per-pixel works.

## Constraints
- Build with `$(PXX_STABLE)`; never rebuild the compiler. A compiler/asm-frontend
  gap → ticket in the owning lane (A / asm), do not work around in the demo.
- **NO automated multithread test without explicit permission** (same guardrail as
  [[feature-demo-mandelbrot-gui-threaded]]): an animation loop pegs cores. Manual-
  validation only; compile-smoke at most in `make demos`. The portable-kernel
  checksum test can stay automated (single-threaded, bounded).
- Palette/zoom math is float and non-deterministic across targets by design — this
  demo is NOT a cross oracle (the portable checksum test is).

## Acceptance
- Phase 1: a TUI Mandelbrot that auto-zooms through the target points with palette
  rotation, rendered by `parallel(pdOnDemand)` scanlines calling the per-target asm
  kernel on x86-64/aarch64 (portable fallback elsewhere); asm kernel escape counts
  proven == portable kernel on a grid; smooth enough to look good; clean quit.
- Phase 2 (later): the GUI variant.

## Log
- 2026-07-17 — Opened on user request: float (allowed to optimize), auto-zoom to
  known points, double-buffer swap, palette + image rotation, per-target asm
  iteration kernel (also a showcase of the asm frontend), parallel scanlines via
  the shipped policy surface. TUI-first, GUI later.
