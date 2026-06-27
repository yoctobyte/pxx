# C: crtl headers miss libc syscall prototypes (fsync, …)

- **Type:** bug / gap (C frontend → crtl headers) — Track C/B boundary
- **Status:** done
- **Owner:** Track CA
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]). Wall after the fn-ptr cast-call fix.
- **Closed:** 2026-06-27

## Symptom

```text
pascal26:31615: error: call to undeclared function: fsync ()
```

sqlite's unix VFS calls `fsync`, `fchmod`, `fchown`, `geteuid`, `read`,
`write`, `close`, `lseek`, `unlink`, `mmap`, … expecting `<unistd.h>` /
`<fcntl.h>` / `<sys/mman.h>` to declare them. pxx's crtl headers
(`lib/crtl/include`) declare some libc functions but not these, so the call
hits the "call to undeclared function" path instead of an extern libc import.

## Likely shape of the fix

Two angles, not mutually exclusive:

1. **(Track B — `lib/crtl`)** add the missing POSIX prototypes to the crtl
   `unistd.h` / `fcntl.h` / `sys/*.h` so the names resolve to libc externs
   (the C extern-binds-libc path already works for `open`/`printf`). This is
   the lib-side, file-ownership-correct home for header content.
2. **(Track C — cparser)** optionally support C89 implicit declaration: an
   undeclared `name(args)` call synthesises an `extern int name()` cdecl import
   (libc) rather than erroring. sqlite does include the headers, so (1) is the
   faithful fix; (2) is a broader convenience and a policy call.

## Fix

Added the narrow sqlite-needed POSIX declarations to `lib/crtl/include/unistd.h`:
`fsync`, `sysconf`, and `_SC_PAGESIZE` / `_SC_PAGE_SIZE`. These declarations
feed the existing C header prototype path, which registers libc extern imports.

The sqlite compile now advances past `fsync` at 31615 and `sysconf(_SC_PAGESIZE)`
at 42642, then stops at a separate C preprocessor `defined(...)` conditional
wall near the unix VFS locking-style block.

## Regression

Added `test/crtl_unistd_fsync_b99.c`, wired into `make test-core`.

## Repro

```c
int main(void){ return fsync(1); }   /* no #include <unistd.h> */
```

## Acceptance

- sqlite advances past 31615; `fsync` and `sysconf` resolve to libc imports.
- A crtl-header smoke test covers the added prototypes.
