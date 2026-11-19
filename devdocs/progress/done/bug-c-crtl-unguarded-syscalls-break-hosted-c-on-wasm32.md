---
track: C
tags: [crtl, wasm32, syscall, regression]
prio: 50
type: bug
blocked-by: []
summary: "Hosted C on wasm32 has not compiled since b3c5f711ea (2026-11-14, the toybox commit): `lib/crtl/src/fcntl.c:56: undeclared identifier 'SYS_openat'`. sys/syscall.h deliberately names no SYS_* on wasm32 and expects callers to guard with `#ifdef SYS_x` and fail ENOSYS. That commit added ~18 unguarded syscall(SYS_x, ...) calls. test/c_wasm32_hosted_stdio.c fails to compile, and so presumably does c_wasm32_math_h; c_wasm32_variadic (no crtl) still passes."
status: done
owner: pxx2
---

# Unguarded crtl syscalls break hosted C on wasm32

Found 2026-11-19 by claude-dupwt while checking d50d6cdce6, which was not the
cause: the published latest at b5e45aa237 fails identically.

```
$ compiler/pascal26 --target=wasm32 test/c_wasm32_hosted_stdio.c x.wasm
pascal26:56: error: undeclared identifier 'SYS_openat' used as value
  in: compiler/../lib/crtl/src/fcntl.c
```

## Cause

b3c5f711ea (`c: toybox 0.8.15 builds and runs (x86-64)`, written by this
seat) added syscall veneers with no wasm32 arm. Its additions:

openat (non-AT_FDCWD path), fadvise64 / fadvise64_64 / arm_fadvise64_64,
eventfd2, mlockall, munlockall, prlimit64, statx, fchmodat, mkdirat, mknodat,
unlinkat, readlinkat, fchownat, faccessat. fchmodat2 and faccessat2 are
already guarded.

`lib/crtl/include/sys/syscall.h`'s `#elif defined(__wasm__)` arm explains why
it is empty on purpose: a wasm32 program that wants a kernel service wants a
WASI import, and a caller guards and returns ENOSYS.

## Fix shape

`#ifdef SYS_x` around each call, with `errno = ENOSYS; return -1;` in the
`#else` arm. Acceptance: c_wasm32_hosted_stdio and c_wasm32_math_h match gcc
again under wasmtime, and toybox still builds on x86-64.

Lane: crtl (pxx2). Offered to pxx2 on 2026-11-19, and no crtl file was touched
before their answer.

## Closed 2026-11-19

Fixed in 89e01b7a10: 24 call sites guarded `#ifdef SYS_x ... ENOSYS`. Details
in done/bug-c-crtl-wasm32-unguarded-syscall-numbers.md. c_wasm32_math_h then
showed a second bug from the same commit (C file-scope initialisers did not run
on wasm32), which frank-user fixed in dc9ad070c3. All three C wasm32 rows match gcc.
