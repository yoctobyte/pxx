---
prio: 58  # auto
---

# crtl gaps surfaced by the undeclared-identifier warning: rmdir, F_OK/W_OK/R_OK, register

- **Type:** bug cluster (crtl completeness + one cfront keyword gap) —
  **Track B** (`lib/crtl`) for rmdir + the access() constants; **Track C**
  (cfront) for the `register` keyword.
- **Status:** backlog
- **Found / Opened:** 2026-07-10, immediately after the undeclared-identifier
  warning landed ([[bug-a-libcfree-unresolved-extern-silent-zero]], commit
  afa42ddd) — building sqlite now prints these instead of silently emitting 0.

## Findings (all currently silent nulls / wrong values)

1. **`rmdir` — same null-call class as pread.** `lib/crtl` has no C `rmdir`
   wrapper, though the PAL already provides `PalRmdir`/`PalBackendRmdir`
   (unlinkat + AT_REMOVEDIR). sqlite references it; today it decays to a 0 slot.
   Fix: add `__pxx_rmdir` (pxxcio.pas → PalRmdir) and a `rmdir()` C wrapper in
   `lib/crtl/src/unistd.c`, prototype in `unistd.h` — mirror the
   ftruncate/access set added in commit d65d95d8.

2. **`F_OK` / `W_OK` / `R_OK` / (`X_OK`) undefined.** The `access()` mode
   constants are not defined by the crtl (`fcntl.h`/`unistd.h`), so
   `access(path, F_OK)` passes mode 0 by accident — wrong, and only "works"
   because F_OK==0. Define them (`F_OK 0, X_OK 1, W_OK 2, R_OK 4`) in the crtl
   header that declares `access`.

3. **`register` reaches the value path.** The C storage-class keyword `register`
   is not modelled by cfront, so it falls through to the identifier/value path
   and warns. Harmless at runtime (it's a no-op qualifier) but it should be
   consumed as a storage-class specifier in the declarator parser, like
   `static`/`const`/`volatile`. Track C.

## Acceptance

- Building sqlite (and the crtl guards) emits **no** `undeclared identifier`
  warnings for `rmdir`, `F_OK`, `W_OK`, `R_OK`, or `register`.
- `rmdir` round-trips libc-free (mkdir a dir, rmdir it, stat → ENOENT); add to
  the b238-style crtl POSIX-IO guard.
- c-testsuite still 220/220; self-host byte-identical.
