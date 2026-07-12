---
prio: 30  # ESP parked (user 2026-07-12): Pascal has prio; also runtime-blocked on bug-esp-idf-heap-linux-mmap-ecall
---

# ESP PAL: exact POSIX fd semantics over ESP-IDF VFS

- **Type:** feature (Track B PAL / ESP-IDF)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-21 (PAL file IO expansion)
- **Relation:** follows `feature-platform-abstraction-layer`

## Problem

The first ESP-IDF PAL file backend uses newlib stdio (`fopen`/`fread`/`fwrite`/
`fseek`/`fflush`/`fclose`) over ESP-IDF VFS. That gives real file contents on
mounted IDF filesystems without touching compiler code, but it is not exact
POSIX fd semantics:

- `PAL_OPEN_EXCL` returns `PAL_ERR_UNSUPPORTED` on ESP for now.
- Standard PAL handles `0`/`1`/`2` are not mapped to ESP-IDF stdin/stdout/stderr.
- Errors collapse to `-1` for stdio failures instead of preserving errno-style
  negative codes.
- Seek offsets are limited by the C `fseek`/`ftell` surface used here.

Direct IDF/POSIX `open`/`read`/`write`/`close` would be a better long-term
match, but `read`/`write` are Pascal keyword tokens today, so a clean direct
external binding needs either imported C declarations with safe Pascal names or
a compiler-supported external symbol alias that preserves the local Pascal
identifier.

## Acceptance

- ESP PAL can open files with exact create/exclusive/truncate/append semantics.
- ESP PAL preserves errno-style negative results consistently with POSIX PAL.
- `PAL_STDIN`/`PAL_STDOUT`/`PAL_STDERR` work on ESP-IDF where the app has
  configured console VFS.
- The implementation is validated by an ESP-IDF link/run smoke on C3 and S3, not
  only host `--platform=esp` unsupported-path tests.

## Log

- 2026-06-21 — Opened while extending PAL file IO. Current stdio-backed ESP path
  is source/object-valid and imports the expected IDF/newlib symbols, but exact
  fd semantics are intentionally left as this follow-up rather than hidden in
  PAL workarounds.
