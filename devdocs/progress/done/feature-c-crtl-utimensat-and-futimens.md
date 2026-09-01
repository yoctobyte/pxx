---
slug: feature-c-crtl-utimensat-and-futimens
title: "crtl has no utimensat/futimens, so busybox's `touch` cannot be built"
track: C
prio: 45
type: feature
status: done
created: 2026-09-01
found-by: frankD
owner: frankD
blocked-by: []
summary: "DONE 2026-09-02. One PAL entry, not two: futimens(fd, ts) IS utimensat(fd, NULL, ts, 0), so PalUtimensat carries both and a NIL path is the futimens spelling rather than an error. The nanosecond fields pass through untouched because they also carry UTIME_NOW and UTIME_OMIT, which is how `touch -a` and `touch -m` work at all; they are marshalled as NATIVE words, since a 32-bit kernel timespec is two 32-bit fields. The syscall number was already in platform_backend.pas for every arch -- PalBackendUtimes had been using it as one fixed case. Verified byte-identical to glibc on four rows including UTIME_OMIT and ENOENT.
---

# utimensat / futimens

Found by attempting a 27-applet busybox userland for
[[feature-c-corpus-busybox-multi-applet]]. `coreutils/touch.c` is the only
consumer, and it is the only reason the differential runs 26 applets.

## The gap is ENUMERATED, not open-ended

The useful part of the attempt was turning "what else is missing?" into a list.
gcc, pointed at crtl's headers instead of the system's, reports the whole
surface at once:

```
gcc -fsyntax-only -nostdinc -isystem lib/crtl/include -I. -Iinclude -Ilibbb \
    busybox_unity.c
```

That named seven things. **Five are now closed**: `clearenv`, `putenv`, `sync`,
and the constants `AT_FDCWD` `AT_SYMLINK_NOFOLLOW` `AF_UNIX` `SOCK_RDM`
`SOCK_SEQPACKET`. `alloca` is a false positive — pxx handles it internally and
only `-nostdinc` hides the builtin declaration. **These two remain.**

Use that invocation before adding applets; it beats discovering one gap per
full unity rebuild, which is how this started.

## The real difficulty is the syscall NUMBER, not the code

The code is a PAL chain exactly like `PalSync`'s, landed the same day:
crtl `utimensat` -> `__pxx_utimensat` -> `PalUtimensat` -> `PalBackendUtimensat`,
plus a `struct timespec[2]` crossing the boundary.

What is NOT routine is the number, and `sync` is the worked example of why:

| arch | sync | utimensat | how sync's number was obtained |
| --- | --- | --- | --- |
| x86-64 | 162 | 280 | read off this box's `asm/unistd_64.h` |
| i386 | 36 | 320 | read off this box's `asm/unistd_32.h` |
| aarch64 | 81 | 88 | asm-generic; sync(81) sits below fsync(82) |
| riscv32 | 81 | 88 | asm-generic, same table |
| arm32 | 36 | 348 | **argued, not sourced** — arm EABI keeps the legacy low numbers |
| xtensa | — | — | **unknown; refuses** |

Two warnings for whoever does this:

- **arm32 breaks the argument that worked for sync.** sync is 36 on both i386
  and arm32, so "arm keeps the legacy numbers" held. utimensat is 320 on i386
  and 348 on arm32 — added at different times, so they diverge. The reasoning
  that got sync right gets utimensat WRONG. Source it.
- **xtensa's numbers in `platform_backend.pas` were obtained EMPIRICALLY**, one
  syscall per process (their table's own note explains why: a bogus call kills
  the process and shifts every later reading). utimensat was never among them.
  `PalBackendSync` refuses on xtensa rather than guessing, and this should too.

## Verify it the way PalSync was verified

`sync()` returns void, so C cannot tell success from refusal — the C-level test
printed `errno=0` on every target INCLUDING the ones that refuse. The check
that discriminates calls the PAL directly and reads the raw status:

```
PalSync=0    on x86_64, i386, aarch64, arm32, riscv32
PalSync=-38  with SYS_sync deliberately set to 9999   <- the control
```

Do that before believing a number.


## DONE 2026-09-02

The ticket said the honest blocker was that the syscall number could not be
sourced for arm32 or xtensa. **It did not need to be**: `SYS_utimensat` was
already in `platform_backend.pas` for every arch, because `PalBackendUtimes`
has been issuing it all along as one fixed case (AT_FDCWD, no flags, both
nanosecond fields zero). The general call sits beside it and the specific one
is unchanged.

xtensa refuses with `PAL_ERR_UNSUPPORTED`, as it does for the other calls whose
numbering this repo has not measured. esp and wasi refuse with a reason each.

**One PAL entry rather than two.** `futimens(fd, ts)` *is*
`utimensat(fd, NULL, ts, 0)` — the kernel defines it that way — so a second
entry would be a second path to keep in step for nothing.

Verified byte-identical to a gcc build of `test/c_crtl_utimensat.c`, whose row
2 is the discriminator: `UTIME_OMIT` in `tv_nsec` beside a `tv_sec` the kernel
must ignore.

## Log

- 2026-09-02 frankD — done, commit 87144b8d3.
