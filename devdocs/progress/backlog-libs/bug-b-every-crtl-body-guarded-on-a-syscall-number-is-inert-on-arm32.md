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
summary: "**THE STATED BLOCKER IS GONE. A cross toolchain is not needed: the numbers are MEASURABLE on this box, and all ten rows below now have verified arm32 numbers.** frankA supplied eight by `qemu-arm -strace` (number -> name, one inert syscall per process), franks-ab settled the remaining two (acct=51, statfs=99) and verified all ten BEHAVIOURALLY -- making the call by raw number on arm32 and matching errno against the same NAMED call on targets that have a real table. The two methods fail differently: strace reads QEMU\'s name table, the behavioural check asks a kernel. Numbers: sched_getscheduler 157, sched_getparam 155, sched_yield 158, mlock 150, munlock 151, flock 143, prctl 172, readv 145, acct 51, statfs 99. **A LIMIT ON THE BEHAVIOURAL HALF, found by its control FAILING TO FAIL: an ADJACENT number in the same family answers identically** -- readv=145 and writev=146 both give EBADF for a bad fd, so behaviour proves \"right family, right argument kinds\" and only strace discriminates siblings. Controls that do work: an unassigned number (399) gives ENOSYS, getpid (20) returns a pid. So the fix is a GENERATED header from a full 0..450 sweep with BOTH controls asserted in the generator -- read/write naming, plus a sibling row that must differ -- not a transcription. ORIGINAL REPORT: MEASURED on all five hosted targets with one probe: ten crtl functions (sched_getscheduler, sched_getparam, sched_yield, mlock, munlock, acct, statfs, flock, prctl, readv) answer errno=ENOSYS on arm32 and behave like the kernel on x86-64, i386, aarch64 and riscv32. Cause is not a bug in any body -- `lib/crtl/include/sys/syscall.h` has NO `__arm__` arm at all, so every `#ifdef SYS_x` in crtl takes its `#else errno = ENOSYS` path. The population is 56 guards across 19 files (sched.c, unistd.c, fcntl.c, sys/{timex,prctl,select,shm,reboot,file,msg,personality,swap,uio,mman,sem,mount,klog,statfs}.c, linux/capability.c), asking for 55 distinct SYS_ names. THE HEADER'S OWN COMMENT IS TRUE AND SHOULD NOT BE 'FIXED': it says arm32 and xtensa get nothing deliberately, because no header on this box gives either table and a guessed number is worse than a missing one -- a wrong number does not fail, it runs a DIFFERENT syscall. Confirmed there is still no source: ~/.cache/pxx-cross/arm32 holds only `lib`, no headers. THE TEMPTING FIX DOES NOT WORK AND THAT IS THE USEFUL PART: platform_backend.pas carries a hand-maintained, use-proven arm32 table of 80 numbers, and its overlap with the 55 crtl wants is THREE (SYS_fork, SYS_ioctl, SYS_ppoll, measured under LC_ALL=C after comm warned about sort order). So transcribing from the PAL buys almost nothing and spends the provenance rule. This needs a real arm32 asm/unistd.h, from a cross toolchain or an arm32 kernel-headers package, fed to the same generator that made the other four arms."
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

## UPDATE 2026-09-04 — the blocker was wrong, and the numbers are measurable here

This ticket said the fix needs *"a real `asm/unistd.h` for arm32 EABI, from a
cross toolchain or a kernel-headers package"*. **frankA showed that is not
required**, and the method is the one `platform_backend.pas`'s xtensa block
already documents for its own numbers: `qemu-arm -strace`, one syscall per
process, every argument `2147483647` so the call is inert whatever it turns out
to be. It goes **number → name**, so a sweep over 0..450 yields the whole map
from one compile and N runs.

### Verified here, by a method that fails differently

frankA's eight were not taken on report. `qemu-arm -strace` reads **QEMU's**
syscall table — genuinely independent of ours, but an oracle about qemu. The
check run here instead makes the call **by raw number on arm32** and compares
`errno` against the same call **by name** on the targets that have a real
table. That asks a kernel rather than a name table.

| name | arm32 # | oracle (i386 / x86-64 / aarch64 / riscv32) | arm32 by number |
| --- | --- | --- | --- |
| `sched_getscheduler` | 157 | rc=0 | rc=0 |
| `sched_getparam` | 155 | -1 EINVAL | -1 EINVAL |
| `sched_yield` | 158 | rc=0 | rc=0 |
| `mlock` | 150 | rc=0 | rc=0 |
| `munlock` | 151 | rc=0 | rc=0 |
| `flock` | 143 | -1 EBADF | -1 EBADF |
| `prctl` | 172 | -1 EINVAL | -1 EINVAL |
| `readv` | 145 | -1 EBADF | -1 EBADF |
| `acct` | **51** | -1 EPERM | -1 EPERM |
| `statfs` | **99** | -1 ENOENT | -1 ENOENT |

The expected errnos DIFFER across rows (0, EINVAL, EBADF, EPERM, ENOENT) on
purpose — a probe whose rows all expect the same value cannot tell a right
number from a wrong one that also fails.

The last two are the pair frankA's sweep produced no line for. The legacy-table
values 51 and 99 answer EPERM and ENOENT, matching the oracle on three targets.

### `readv` needed a sharper probe, and that is worth keeping

The first attempt used `readv(-1, NULL, 0)` and arm32 answered rc=0 where i386
answered EBADF — which reads as a wrong number. It is not: **with `iovcnt` 0 a
kernel may return 0 without ever looking at the fd**, so that row was not
evidence about the number at all. With a real `iovec` and `iovcnt` 1, all four
tabled targets AND arm32-by-number answer EBADF. An ambiguous argument shape
produced a confident wrong reading.

### THE CONTROL FAILED TO FAIL, and that is the real limit of this method

The first negative control was `145 + 1`. It also answered EBADF — because
**146 is `writev`, and `writev(-1, iov, 1)` is EBADF too.** An adjacent number
in the same family is indistinguishable behaviourally.

So the behavioural check proves *"this number reaches a call in the right family
taking these argument kinds"* and **cannot discriminate siblings**. Controls
that do discriminate:

    #399 (unassigned)  -> -1 ENOSYS
    #20  (getpid)      -> returns a pid, errno 0

`qemu-arm -strace` does not have this weakness — it names the call — which is
exactly why the two methods belong together rather than either alone.

### So the fix is a GENERATED header, not a transcription

A full 0..450 sweep, emitted by the same generator that made the other four
arms, with **both controls asserted inside the generator**:

1. the `read`/`write` naming rows frankA already checks (3 and 4 on arm32),
2. **and a sibling row that must DIFFER** — otherwise the generator's own guard
   has the hole this ticket's control just fell into.

Provenance caveat to carry into the header, frankA's and correctly stated
(`36758dae3`): qemu's names come from QEMU's table, so a qemu/kernel divergence
is invisible and looks exactly like a correct number. The mitigation for arm32
is that **every arm32 test in this tree runs under qemu-arm**, so the numbers
are right for the entire population that exercises them. Say that in the header
rather than "measured".

