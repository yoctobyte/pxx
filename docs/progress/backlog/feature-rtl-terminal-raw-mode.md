# Terminal raw mode and unbuffered input support (libc-free)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-21
- **Relation:** Stresses terminal state configuration and unbuffered input handling. Blocker for feature-demo-file-browser and feature-demo-video-player.

## Goal

Provide a statically-linked, libc-free terminal raw mode toggle in `ansiterm` to read keyboard events character-by-character without waiting for Enter.

## Surface (sketch)

In `lib/rtl/ansiterm.pas`:
- `procedure AnsiSetRawMode(enable: Boolean);`
- `function AnsiReadKey: Char;` (or equivalent non-blocking read)

## Implementation Steps

1. Bind the `TCGETS` and `TCSETS` constants (ioctl request codes) in the RTL.
2. Implement terminal state reading and writing via `sys_ioctl` (Syscall 16 on x86-64).
3. Implement `AnsiSetRawMode` which reads current state, clears `ICANON` and `ECHO` flags, sets minimum characters to 1, and writes back.
4. Restore standard terminal state upon program exit or crash (via an exit handler or try/finally).

## Log
- 2026-06-21 — Opened.
