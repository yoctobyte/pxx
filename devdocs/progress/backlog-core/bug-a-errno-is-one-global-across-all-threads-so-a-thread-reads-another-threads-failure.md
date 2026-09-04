---
slug: bug-a-errno-is-one-global-across-all-threads-so-a-thread-reads-another-threads-failure
title: "errno is one global across all threads, so a thread can read another thread's failure code"
track: A
prio: 65
type: bug
status: backlog
created: 2026-09-04
found-by: franks-ab
owner: ""
blocked-by: []
summary: "MEASURED, reproduced independently by two sessions: a threaded pxx C program shares ONE errno across all threads, where C requires it thread-local. Two threads provoking different errors and reading errno on the very next line see each other's codes 4-84 times per 200000 iterations, varying per run as a race should; the gcc/glibc oracle is 0 every time. --threadsafe does NOT fix it -- that flag selects a real thread PAL and threads genuinely run, so the one flag a reader would expect to cover this is the one that silently does not. Root: lib/crtl/include/errno.h:5 declares `extern int errno;` (an ordinary int) where glibc has `#define errno (*__errno_location())`; the tentative definition becomes a WEAK non-TLS .bss object in every pxx object file. The visible symptom is a static-link refusal (ld: TLS vs non-TLS mismatch against libc.a), but that is the LUCKY case -- it stops and names the symbol. The dynamic link tolerates the mismatch and nothing errors anywhere. Fix needs TLS symbol emission in the object writer, so it is Track A rather than lib/crtl alone."
---

# errno is one global, not one per thread

## The measurement

The probe asserts a RELATION, not a constant — *"a thread only ever sees the
errno its own call produced"* — so it carries no per-platform value and is
correct against any libc. Two threads, 200000 iterations each: thread A calls
`open()` on a missing path (`ENOENT`), thread B calls `close(-1)` (`EBADF`),
and each reads `errno` back on the very next line and counts how often it sees
the *other* code.

| build | thread A wrong | thread B wrong |
| --- | --- | --- |
| gcc / glibc (oracle) | 0 | 0 |
| pxx x86-64 `--threadsafe`, pinned v403 `c31d03b2` | 4 | 84 |
| pxx x86-64 `--threadsafe`, `1968c7a7da57` (frankD, 3 runs) | 8 / 21 / 6 | 12 / … / 8 |
| pxx **i386** `--threadsafe`, `1968c7a7da57` (frankD) | 21 | 26 |

Nonzero every run, varying as a race should. glibc is 0 every run. Reproduced
independently by franks-ab and frankD, on different compiler builds, with
separately written probes.

**One of the two readings used the PINNED v403 compiler**, which rules out "this
landed after the pin" — the one alternative explanation available. Two readings
that could have failed the same way would have been one reading.

**It is WIDTH-INDEPENDENT (i386 row above), and that is an acceptance
constraint rather than a curiosity.** `extern int errno;` is a 4-byte int at
both widths and TLS-versus-not is orthogonal to pointer size, but orthogonal in
principle is not a measurement and now it is one. The usual hazard in this repo
is the opposite one — width and alignment bugs being structurally invisible on
the x86-64 host that the dev loop, `gate.sh quick` and the pin all run on. Here
the bug is present at BOTH widths, so the risk is symmetric: **a fix verified
only on the host would look complete.**

**The rate is a FLOOR, not an estimate.** Both probes read `errno` on the very
next line, so the window is a few instructions. Real code does work between the
failing call and the check — a log line, cleanup, another call — and the window
scales with that work. Do not quote 0.004% as the exposure.

## Root cause

`lib/crtl/include/errno.h:5`

    extern int errno;

an ordinary `int`, where glibc has `#define errno (*__errno_location())` and C11
7.5 requires `errno` to be thread-local. The tentative definition becomes a weak
non-TLS object in every translation unit:

    pxx object   errno  OBJECT WEAK  4 bytes, section .bss   (non-TLS)
    glibc        errno  TLS GLOBAL   4 bytes                 (.tbss)

## Why the linker error is the good half

Static linking REFUSES the mismatch outright:

    ld: errno: TLS definition in libc.a(errno.o) section .tbss
        mismatches non-TLS definition in obj/coreutils_cat.o section .bss

That is the lucky case: it stops, it names the symbol, and the fix is forced.
**The dynamic link tolerates it**, which is the expensive outcome — every
threaded pxx program that reads `errno` after a failing call can read a value
another thread wrote in between, with nothing erroring anywhere. `errno` is
close to the worst variable for this: it is read immediately after a failure and
branched on, so a corrupted read becomes a wrong control-flow decision far from
its cause.

## `--threadsafe` does not cover it, and that is part of the bug

Without the flag the compiler refuses, and the refusal is a good one:

    __pxx_pmutex_init needs the thread-safe runtime: rebuild with --threadsafe
    (<pthread.h> lowers onto the pxx thread PAL, which that flag selects)

So the flag exists, it selects a real thread PAL, and threads genuinely run —
`lib/crtl/src/pthread.c:108` implements `pthread_create` over
`__pxx_pthread_create`. The flag a reader would expect to make threading correct
is exactly the one that leaves `errno` shared, so nobody gets a warning.

## Repro

    ./stable_linux_amd64/default/pinned --threadsafe errno_race.c out && ./out
    gcc -O1 -o oracle errno_race.c -lpthread && ./oracle     # the oracle

Probe source: see the table above for the shape; it is ~40 lines and asserts
only the relation, so it needs no expected constants.

## Acceptance — a row per target, not one green on the host

If the repair grows TLS symbols in the emitter, **each backend has to grow them
separately**, so one green on x86-64 does not close this. The acceptance wants a
row for every target with an object writer.

**Assert the RELATION the probe already asserts — zero foreign errno values —
never a per-target constant.** It passes everywhere, needs no expected value,
and therefore cannot be satisfied by an expected value that collides with the
failure value. The probe's positive control is free and already demonstrated:
the pre-fix build must come out NONZERO, and it does, on every target measured
so far.

## What the fix needs

`extern int errno;` cannot become thread-local without the emitter growing TLS
symbols, so this is **Track A object-writer work**, not a lib/crtl edit. Filed
from Track B, where it surfaced.

Related: [[meta-a-pxx-produces-linkable-code]] is the standing umbrella for
object/link/export work and already records a DIFFERENT errno fix (two objects
each reading their own errno, fixed in 243137302 by relocating an exported
definition against its own symbol). That one made two objects share one errno;
this one is that shared errno not being per-thread. They are not the same bug
and the first does not imply the second.

## Bound it puts on other work

`feature-b-a-bootable-image-with-the-busybox-userland-on-it` (rung 3) cannot
produce a STATICALLY linked pxx-built busybox until this is fixed, so that image
carries a dynamic busybox plus libc. The same bound applies to frankD's i386
axis. The kiosk finding *"pascal26 and everything it emits are statically
linked"* is true of pxx's own ELF writer output and does NOT extend to anything
the separate-compilation path produces, because that path ends in
`gcc -o out obj/*.o`, which links dynamically by default.
