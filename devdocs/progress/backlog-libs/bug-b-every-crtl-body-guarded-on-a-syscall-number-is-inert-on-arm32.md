---
slug: bug-b-every-crtl-body-guarded-on-a-syscall-number-is-inert-on-arm32
title: "every crtl body guarded on a SYS_ number answers ENOSYS on arm32 — 56 guards across 19 files, because <sys/syscall.h> has no arm32 arm"
track: B
prio: 55
type: bug
status: backlog
created: 2026-09-04
found-by: franks-ab
owner: ""
blocked-by: []
summary: "MEASURED on all five hosted targets with one probe: ten crtl functions (sched_getscheduler, sched_getparam, sched_yield, mlock, munlock, acct, statfs, flock, prctl, readv) answer errno=ENOSYS on arm32 and behave like the kernel on x86-64, i386, aarch64 and riscv32. Cause is not a bug in any body -- `lib/crtl/include/sys/syscall.h` has NO `__arm__` arm at all, so every `#ifdef SYS_x` in crtl takes its `#else errno = ENOSYS` path. The population is 56 guards across 19 files (sched.c, unistd.c, fcntl.c, sys/{timex,prctl,select,shm,reboot,file,msg,personality,swap,uio,mman,sem,mount,klog,statfs}.c, linux/capability.c), asking for 55 distinct SYS_ names. THE HEADER'S OWN COMMENT IS TRUE AND SHOULD NOT BE 'FIXED': it says arm32 and xtensa get nothing deliberately, because no header on this box gives either table and a guessed number is worse than a missing one -- a wrong number does not fail, it runs a DIFFERENT syscall. Confirmed there is still no source: ~/.cache/pxx-cross/arm32 holds only `lib`, no headers. THE TEMPTING FIX DOES NOT WORK AND THAT IS THE USEFUL PART: platform_backend.pas carries a hand-maintained, use-proven arm32 table of 80 numbers, and its overlap with the 55 crtl wants is THREE (SYS_fork, SYS_ioctl, SYS_ppoll, measured under LC_ALL=C after comm warned about sort order). So transcribing from the PAL buys almost nothing and spends the provenance rule. This needs a real arm32 asm/unistd.h, from a cross toolchain or an arm32 kernel-headers package, fed to the same generator that made the other four arms."
---

# crtl on arm32: every syscall-guarded body is inert

## The measurement

One probe, five targets. Each row is a call whose only failure mode here is a
missing number — it is given arguments the kernel refuses cheaply, so a target
WITH the table answers some other errno (or 0) and one without it answers
ENOSYS. **errno is printed, not rc: rc is -1 either way**, which is the whole
reason this is invisible.

| call | x86-64 | i386 | aarch64 | riscv32 | **arm32** |
| --- | --- | --- | --- | --- | --- |
| `sched_getscheduler` | 0 | 0 | 0 | 0 | **38 ENOSYS** |
| `sched_getparam` | 0 | 0 | 0 | 0 | **38** |
| `sched_yield` | 0 | 0 | 0 | 0 | **38** |
| `mlock` | 0 | 0 | 0 | 0 | **38** |
| `munlock` | 0 | 0 | 0 | 0 | **38** |
| `acct` | 1 | 1 | 1 | 1 | **38** |
| `statfs` | 0 | 0 | 0 | 0 | **38** |
| `flock` | 9 | 9 | 9 | 9 | **38** |
| `prctl` | 22 | 22 | 22 | 22 | **38** |
| `readv` | 9 | 9 | 0 | 0 | **38** |

`readv` differs between the 32- and 64-bit rows (9 against 0) for a reason
unrelated to this ticket — a NULL iovec with count 0 is handled differently —
and it is left in rather than trimmed, because a table with an unexplained cell
quietly removed is worse than one that says which cell it cannot explain.

## The population

    56 guards, 19 files, 55 distinct SYS_ names

`sched.c`, `unistd.c`, `fcntl.c`, `sys/timex.c`, `sys/prctl.c`, `sys/select.c`,
`sys/shm.c`, `sys/reboot.c`, `sys/file.c`, `sys/msg.c`, `linux/capability.c`,
`sys/personality.c`, `sys/swap.c`, `sys/uio.c`, `sys/mman.c`, `sys/sem.c`,
`sys/mount.c`, `sys/klog.c`, `sys/statfs.c`.

Every one takes `#else errno = ENOSYS; return -1;` on arm32.

## The header's comment is CORRECT — do not "fix" it

`lib/crtl/include/sys/syscall.h` says arm32 and xtensa get nothing
**deliberately**: no header on this box gives either table, and *"a guessed
number is worse than a missing one — a wrong number does not fail, it runs
something else."* That reasoning is right and this ticket does not dispute it.
Three hundred numbers is exactly the population where one recalled digit
becomes a different syscall.

Still true today: `~/.cache/pxx-cross/arm32` holds only `lib` (the loader and
libc.so that qemu needs), no `asm/unistd.h`. `/usr/include/asm` is this box's
x86-64.

## The tempting fix, and why it is not one

`lib/rtl/platform/posix/platform_backend.pas` carries a hand-maintained arm32
table that is *use-proven* — arm32 tests run through `SYS_kill=37`,
`SYS_getpid=20`, `SYS_rt_sigaction=174` every day. So "copy the numbers from
the PAL" looks obvious and cheap.

**Measured, it buys three numbers.**

    crtl guards want          55 distinct SYS_ names
    platform_backend arm32    80 numbers
    OVERLAP                    3  -- SYS_fork, SYS_ioctl, SYS_ppoll

None of the ten rows in the table above is among them. The two sets barely
intersect because they answer different questions: the PAL carries what the
RUNTIME needs, and these guards are what a PROGRAM reaches for when the PAL has
no entry. So the transcription spends the provenance rule and fixes nothing
measurable.

(Count taken under `LC_ALL=C`. The first run warned *"comm: file 1 is not in
sorted order"* and printed a number anyway — an instrument that answers while
telling you it cannot.)

## What would actually fix it

A real `asm/unistd.h` for arm32 EABI, from a cross toolchain or a
kernel-headers package, fed to the **same generator** that produced the
x86-64/i386/aarch64/riscv32 arms. Provenance, not transcription. xtensa is the
same shape and the same answer.

## Acceptance

The table above, with the arm32 column matching i386 row for row — it is the
same word size and the same kernel, so a per-target constant is not needed and
the assertion is **agreement between two targets**, which carries no expected
value to go stale.

Worth pairing with
[[bug-b-crtl-waitpid-returns-enosys-on-riscv32-so-no-program-can-reap-a-child]]
— different cause, same symptom shape, and both were found by running a C probe
on a cross target rather than by reading the source.

## Found by

Following up frankA's *"if you hit a fourth private syscall table in crtl, the
PAL almost certainly already has the numbers"* (`c4c5e932b`, after deleting
pxxcio's two and ansiterm's four). Checked, and crtl's is the opposite shape:
its table is the generated, authoritative one and the PAL cannot supply what it
is missing. The advice was right to check and wrong for this file, which is
itself worth recording.
