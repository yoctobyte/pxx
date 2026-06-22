# Demo — GUI Mandelbrot, multithreaded tiled zoom

- **Type:** feature
- **Track:** B
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-22
- **Relation:** Builds on `feature-demo-mandelbrot` (compute kernel + native-asm
  path) and the existing `examples/mandelbrot/mandelbrot.pas` (portable Double
  escape-time kernel + deterministic checksum oracle). GUI via `lib/pcl`
  (`gtk3`, `glarea`). Phase 3 leans on `feature-parallel-processing` /
  `feature-async-language-surface`.

## Goal

An interactive **GUI** Mandelbrot with fast zooming on a **tiled surface**, where
the headline feature is **multithreaded** rendering (use real cores so deep
zooms stay responsive). Console vs GUI was open; **GUI preferred** (smooth
interactive pan/zoom). The multithreading is the point of the ticket.

## Phased plan

1. **Mono-thread GUI.** GTK3/GL window (`lib/pcl`), tiled framebuffer, interactive
   pan/zoom/reset, progressive/tiled redraw so a zoom paints coarse→fine. Reuse
   the existing portable Double escape-time kernel. Single render thread.
2. **Multithread.** Split the viewport into tiles, farm them to worker threads
   (work queue), recombine into the surface; redraw tiles as they finish.
   **Prerequisite gap:** the RTL has only *cooperative* concurrency
   (`channel`/`coroutine`/`scheduler`/`syncobjs`) — there is **no OS-thread
   primitive** (no `PalThread`/`clone(CLONE_THREAD)`). Real multicore needs a PAL
   thread-spawn (clone with shared VM + a per-thread stack) + join + a mutex.
   File/own that as a sub-task (PAL, like the recent process-spawn work) before
   this phase can use multiple cores.
3. **Language-level parallel processing (big to-do).** Re-express the tile loop
   with the language's parallel constructs instead of manual threads — depends on
   `feature-parallel-processing` / `feature-async-language-surface` maturing.
   Lowest priority; do phases 1–2 first.

## Constraints

- **NO automated tests without explicit permission.** A multithreaded render
  (especially repeated in a test loop) can peg every core to 100% and lock the
  machine. This demo is **manual-validation only** unless the user explicitly
  asks for a smoke test — and any such test must be opt-in, bounded (tiny image,
  low iteration cap, single short run, thread count capped). Do NOT wire it into
  `make lib-test`/`make demos` as a runtime test; compile-smoke at most.
- Platonic source; GUI via `lib/pcl`; any math/runtime/compiler gaps found stay
  filed as separate tickets.
- The existing console `examples/mandelbrot/mandelbrot.pas` keeps its
  deterministic checksum oracle; this GUI/threaded demo is visual + interactive
  and is not a deterministic oracle.

## Acceptance

- Phase 1: a usable GUI Mandelbrot with interactive pan/zoom and tiled redraw,
  compiles with `$(PXX_STABLE)`, runs on the host (manual check).
- Phase 2: tiles rendered across N worker threads with a visible speedup on deep
  zooms; clean thread shutdown on quit; no automated stress test added without
  permission.
- Phase 3: the tile loop expressed via language parallel constructs (separate
  follow-up once those land).

## Log
- 2026-06-22 — Opened on user suggestion: GUI, fast interactive tiled zoom,
  multithreaded as the core feature; phased mono → threads → language parallelism;
  explicit no-automated-multithread-tests-without-permission guardrail.
