# Flagship Demo — Console Video Player (libc-free)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-21
- **Relation:** Sibling to other flagship demos. **Depends on** the low-level process spawning and pipe redirection in feature-sys-process-spawning and terminal input in feature-rtl-terminal-raw-mode.

## Goal

A terminal-based video player (`examples/player/`) that spawns an external `ffmpeg` process, redirects its stdout raw video frames via a pipe, and renders them at 24/30 FPS synchronized to the monotonic system clock.

## Specification

- **Spawning**: Invoke `ffmpeg` in a pipeline:
  `ffmpeg -i input.mp4 -f image2pipe -pix_fmt rgb24 -vcodec rawvideo -`
- **Audio**: Spawn a sibling processes (like `aplay`) to handle audio playback in sync.
- **Sync & Timing**: Read `Width * Height * 3` raw RGB24 frames from the pipe. If behind the monotonic timeline, drop frames. If ahead, sleep.
- **Controls**: Non-blocking key events:
  - `Space` to pause / resume.
  - `q` to quit playback.
  - `g` to toggle rendering quality on-the-fly between `pixelized` (half-block) and `advanced` (quadrant-plus-detail) modes.

## Log
- 2026-06-21 — Opened.
