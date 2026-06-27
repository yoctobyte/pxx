# crtl: `fopen`/`fclose`/`fseek`/`ftell` declared but not defined (no file open)

- **Type:** bug / feature gap (lib/crtl — Track C)
- **Status:** backlog
- **Found / Opened:** 2026-06-27 (Track A+C, while building the `make test-lua`
  suite — the runner had to read the program from stdin because there is no way
  to open a file)

## Symptom

`lib/crtl/include/stdio.h` declares `fopen`, `fclose`, `fseek`, `ftell` (and
`unistd.h` declares `lseek`), but **none are defined** in `lib/crtl/src`. Only
the descriptor-based stream calls exist — `fread`/`fwrite`/`fputs`/`fgetc`/`feof`
ride `__pxx_read`/`__pxx_write` on an already-open `fd`.

Calling `fopen` therefore links to a dynamic libc import (or returns a bogus
`FILE*`); the crtl `fread` then reads `stream->fd` from a layout that is not
libc's `FILE`, so the read fails:

```c
FILE *f = fopen("x.lua", "rb");   /* non-null, but not a crtl FILE */
fread(buf, 1, n, f);              /* reads garbage fd -> fails */
```

Impact: any C program that opens a file (lua `io.open`/`dofile`, config readers,
the natural `make test-lua` runner) cannot. The lua suite works around it by
feeding the program on **stdin** (`__pxx_read(0, …)`), and `liolib.c`'s file API
is effectively dead.

## Fix direction — matches the existing stdio PAL bridge

The Pascal RTL already has a real syscall file-open: `PalOpen(path, flags, mode)`
in `lib/rtl/platform.pas` (used by textfile.pas / sysutils.pas / dns.pas). The C
stdio bridge already binds `__pxx_write`/`__pxx_read` to `PalWrite`/`PalRead` via
the shared-Procs/FindProc mechanism (see the `project_c_stdio_pal_bridge_done`
arc). Extend the same way:

1. Add a thin `__pxx_open(const char *path, int flags, int mode)` /
   `__pxx_close(int fd)` bridge to `PalOpen`/`PalClose` (pxxcio.pas).
2. Define crtl `fopen` (map `"r"/"w"/"a"/"+"/"b"` → PAL flags, allocate a `FILE`
   with the returned fd), `fclose` (`__pxx_close` + free), and the seek family
   (`fseek`/`ftell`/`lseek` → a `PalSeek`/`lseek` syscall bridge; add one if the
   RTL lacks it).
3. Then the `make test-lua` runner can `fopen` the `.lua` path directly instead
   of reading stdin, and lua `io`/`dofile` come alive — basis for the lua-sqlite
   desktop milestone (`feature-c-desktop-lua-sqlite-path`).

Gate: a `crtl` C test that writes a temp file, reopens it, reads it back; plus
`make test-lua` still green.
