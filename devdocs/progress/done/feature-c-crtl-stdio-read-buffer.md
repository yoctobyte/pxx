---
track: C
tags: [crtl, stdio, performance, pathb]
prio: 60
type: feature
blocked-by: []
summary: "crtl streams from fopen/fdopen/popen now read through a 4 KiB buffer. An fgetc loop over 10 MB went from 18.2 s to 0.32 s (glibc 0.09 s), fgets from 20.9 s to 0.35 s. stdin stays unbuffered (Pascal ReadLn reads fd 0 itself), and writes stay unbuffered (feature-c-crtl-stdio-buffering-and-setvbuf). Unread bytes go back to the fd before any write, seek or fflush, so positions behave as before."
status: done
owner: pxx2
---

# crtl stdio: a read buffer for opened streams

## Why

Every `fgetc` was one `read()` syscall. Reading a 10 MB file:

| loop    | before  | after  | glibc  |
|---------|---------|--------|--------|
| fgetc   | 18.2 s  | 0.32 s | 0.09 s |
| fgets   | 20.9 s  | 0.35 s | 0.03 s |

fontconfig, the X font code and any config parser read this way.

## What

- `struct PxxCrtlFile` gains `rbuffered`, `rbuf` (4 KiB, allocated on the
  first read) and `rpos`/`rlen`.
- fopen/fdopen (and so popen) set `rbuffered`. stdin/stdout/stderr don't:
  a mixed program's Pascal ReadLn reads fd 0 directly, and bytes parked in
  a C buffer would be lost to it. That's the same reason the write half
  waits.
- fgetc and fread serve from the buffer. A large fread remainder
  (>= 4 KiB) reads straight into the caller's memory.
- `__crtl_rdrop` seeks the fd back over unread bytes and empties the buffer
  (on a pipe the bytes are dropped, as glibc does). It runs before every
  write (fputc, fputs, fwrite, fprintf, vfprintf), on fflush and on
  setvbuf(_IONBF).
- fseek/fseeko with SEEK_CUR count from the logical position. ftell/ftello
  subtract the unread bytes. rewind, freopen and fclose reset the buffer, and
  fclose frees it.
- If the buffer can't be allocated, the stream reads unbuffered.

## Not covered

- Write buffering: see feature-c-crtl-stdio-buffering-and-setvbuf.
- Two threads reading the same FILE at once. crtl's FILE has no lock, and
  before this each fgetc was a syscall. Use one FILE per thread, or
  `--system-libs`.
- Code that mixes stdio reads with read() on fileno() of the same stream
  sees the buffer, as with glibc. fflush first gives the bytes back.

## Test

test/c_crtl_read_buffer.c, rows c_rdbuf26 and c_rdbuf26_i386,
gcc-compared against glibc. It covers fgetc over 74 KB, ftell, SEEK_CUR in
both directions, SEEK_END, ungetc on top of the buffer, small/large/
past-the-end fread, r+ writes after reads, fflush followed by read() on the
fd, setvbuf(_IONBF), fdopen and popen.
