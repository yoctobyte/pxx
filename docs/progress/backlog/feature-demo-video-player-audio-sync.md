# Video player audio playback and sync

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-21
- **Relation:** Follow-up from validating `feature-demo-video-player`.

## Problem

The console video player compiles and its video chain works with a generated MP4
on pinned v32: `ffmpeg` spawns, raw RGB frames stream through the pipe, ANSI
rendering emits frames, and the child is waited. The original player spec also
listed sibling audio playback (`aplay` or similar), but
`examples/player/player.pas` does not spawn or synchronize audio.

## Direction

- Decide the host-only audio helper (`ffmpeg` audio pipe, `aplay`, or another
  tiny external player).
- Spawn the audio process through the PAL process API.
- Tie pause/quit behavior to both video and audio children, or explicitly
  document the first supported limitation.

## Acceptance

- A short generated video with audio starts both children and exits cleanly.
- Quit/EOF closes pipes and waits for all spawned children.
- The no-audio-video path still works.

## Log
- 2026-06-21 — Opened after Track B validated the existing video-only chain.
