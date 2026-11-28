---
slug: feature-crtl-pipe2
track: crtl
prio: 50
type: feature
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (umbrella-pxx-compiles-systemd slice 1: libcap 2.75 through the make replay)
tags: [crtl, unistd]
summary: "pipe2(2) was missing from <unistd.h>, though crtl's pipe() was already built on the pipe2 syscall (__pxx_pipe2(fds, 0)). It is the one libcap 2.75 unit of 7 that did not compile (psx/cap_launch). Added beside pipe(). Test: c_pipe2_26 checks O_CLOEXEC and O_NONBLOCK on both ends, EAGAIN on an empty non-blocking read, flags 0 as pipe(), and EINVAL for a bad flag, against gcc."
---

# pipe2

libcap 2.75 is built with plain make, its units recorded by
tools/replay/ccrec.py as CC, and the host helper `_makenames` built with
BUILD_CC=gcc. It now replays 7/7.
