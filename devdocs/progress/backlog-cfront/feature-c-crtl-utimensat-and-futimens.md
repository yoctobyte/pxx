---
slug: feature-c-crtl-utimensat-and-futimens
title: "crtl has no utimensat/futimens, so busybox's `touch` cannot be built"
track: C
prio: 45
type: feature
status: backlog
created: 2026-09-01
found-by: frankD
owner: ""
blocked-by: []
summary: "`touch` is the one applet keeping the busybox userland at 26 instead of 27: it calls utimensat() and futimens(), which crtl neither declares nor implements, and no PAL entry exists for either. The rest of the gap that attempt exposed is CLOSED (clearenv, putenv, sync, AT_*/AF_UNIX/SOCK_* constants). The work is a PAL chain like PalSync's, and the honest blocker is that the syscall NUMBER cannot be sourced on this box for arm32 or xtensa."
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
