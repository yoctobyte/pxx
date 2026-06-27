# C: crtl `unistd.h` misses `getpid`

- **Type:** bug / gap (CRTL headers) — Track B/C boundary
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after the sqlite preprocessor
  `defined(...)` wall was fixed.

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

## Acceptance

- sqlite advances past `getpid` at 33288.
- A small CRTL header smoke covers `getpid`.
