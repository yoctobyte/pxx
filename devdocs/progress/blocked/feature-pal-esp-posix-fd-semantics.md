---
prio: 30  # ESP parked (user 2026-07-12): Pascal has prio; also runtime-blocked on bug-esp-idf-heap-linux-mmap-ecall
---

# ESP PAL: exact POSIX fd semantics over ESP-IDF VFS

- **Type:** feature (Track B PAL / ESP-IDF)
- **Status:** backlog — unblocked (bug-esp-idf-heap-linux-mmap-ecall resolved 2026)
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

- 2026-07-19 (backlog sweep note) Stale blocker ref: bug-esp-idf-heap-linux-mmap-ecall is resolved (in done/). Ticket itself still fully open (ESP backend stdio-based, PAL_OPEN_EXCL unsupported).

## Moved to blocked/ (2026-07-20, Track B sweep)

Acceptance is a C3/S3 link-and-run smoke; there is no device and no qemu/IDF
runner in this lane. External constraint, so `blocked/` rather than backlog.

One thing IS doable without hardware and is worth doing first when this resumes:
host-side `--platform=esp` tests that pin the CURRENT behaviour — `PAL_OPEN_EXCL`
returning `PAL_ERR_UNSUPPORTED`, and the errno collapse — so the rewrite has a
baseline to diff against instead of changing semantics blind.

## Moved to blocked/ 2026-07-31 (Track B sweep) — same wall as the rest of the ESP family

This ticket's own acceptance ends with "validated by an ESP-IDF link/run smoke
on C3 and S3, **not only** host `--platform=esp` unsupported-path tests". That
is the part nothing here can do: re-checked rather than assumed, this box has no
`qemu-system-riscv32`, no `qemu-system-xtensa`, `IDF_PATH` unset, and no board.
An ESP-IDF checkout at `~/esp/esp-idf` is enough to LINK and nothing more.

Writing exact POSIX fd semantics that nobody can execute would produce precisely
what the honest-refusal discipline in this backend exists to avoid: code that
looks right. The current newlib-stdio backend already refuses what it cannot do
(`PAL_OPEN_EXCL` -> `PAL_ERR_UNSUPPORTED`), which is the correct resting state.

**Tagged for later testing** with [[feature-esp-peripheral-callback-api]]: when a
C3/S3 board or a working qemu-IDF harness appears, both wake up together. Nothing
from this ticket enters the regression suite until something can run it.
