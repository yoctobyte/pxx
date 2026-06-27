# C: crtl `unistd.h` misses `getpid`

- **Type:** bug / gap (CRTL headers) — Track B/C boundary
- **Status:** done
- **Owner:** Track CA
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after the sqlite preprocessor
  `defined(...)` wall was fixed.
- **Closed:** 2026-06-27

## Symptom

sqlite now advances to:

```text
pascal26:33288: error: call to undeclared function: getpid ()
```

Repro command:

```sh
./compiler/pascal26 -Ilibrary_candidates/sqlite library_candidates/sqlite/sqlite3.c /tmp/sqlite3
```

## Likely Shape

Add the POSIX prototype to `lib/crtl/include/unistd.h`:

```c
int getpid(void);
```

The existing C header import path should register it as a libc extern import,
matching `fsync` / `sysconf`.

## Fix

Added `int getpid(void);` to `lib/crtl/include/unistd.h`.

## Regression

Added `test/crtl_unistd_getpid_b101.c`, wired into `make test-core`.

## Acceptance

- sqlite advances past `getpid` at 33288.
- b101 covers `getpid`.
