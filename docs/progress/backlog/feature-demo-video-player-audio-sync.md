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

## Blocker found + fixed (2026-06-22, Track B)

Investigated "what's holding us back" — the concrete blocker for a second
concurrent child (the audio process alongside video) was an **fd leak / EOF
deadlock**, not exec itself:

`ExecutePipeline` created its pipes with `flags=0` (no `O_CLOEXEC`). The audio
child spawned second inherited the video child's stdin write-end, so closing the
parent's copy never delivered EOF to the first child and `wait()` hung forever.
Reproduced with two `/bin/cat` children (first child's `wait` deadlocked).

**Fixed** in `lib/rtl/sysutils.pas` (commit ab71066): pipes are now `O_CLOEXEC`;
`dup2` in the child clears CLOEXEC on the wired 0/1 fds so they survive exec,
while all other inherited pipe fds auto-close on exec. Regression test
`test/lib_process_multi.pas` (two concurrent children) wired into `make lib-test`.

So concurrent children now work. Remaining for THIS ticket = the actual audio
implementation: spawn an audio sibling (e.g. `ffmpeg ... | aplay` or a second
ffmpeg → `aplay`) through `ExecutePipeline`, feed/sync it against the monotonic
clock, and tie pause/quit/EOF to both children. (Secondary, non-blocking: the
vfork child still runs Pascal with locals on the shared stack — see
feature-sys-process-spawning hardening note.)
