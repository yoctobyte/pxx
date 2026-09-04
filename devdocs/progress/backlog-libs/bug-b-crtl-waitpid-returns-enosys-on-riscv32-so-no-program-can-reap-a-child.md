---
slug: bug-b-crtl-waitpid-returns-enosys-on-riscv32-so-no-program-can-reap-a-child
title: "crtl waitpid() returns -1/ENOSYS on riscv32 while fork() works, so a child can be created and never reaped"
track: B
prio: 60
type: bug
status: backlog
created: 2026-09-04
found-by: franks-ab
owner: ""
blocked-by: []
summary: "MEASURED on riscv32 under qemu-user, with arm32 and aarch64 as controls that PASS under the same emulator, so it is the target and not the emulation. `fork()` succeeds and returns a plausible pid; `waitpid(pid, &st, 0)` then answers -1 with errno=ENOSYS and leaves the caller's status word untouched. The asymmetry is the expensive part -- a program that forks gets a real child and can never learn what happened to it, so every wait-based control flow (a shell, an init, any run-a-command helper) either hangs or proceeds on an uninitialised status. Probable cause, NOT yet confirmed in the source: rv32 is one of the linux ports that does not carry the legacy `wait4` number at all (it expects `waitid`), so a PAL entry written against wait4's number has nothing to call. x86-64 and arm32 both answer correctly with the same crtl and the same probe, which rules out the C side. Found while cross-checking test/c_crtl_signal_dispositions.c: its row 5 asserts SIG_DFL reverts by watching a CHILD die of the signal, and that row is the only one of nine that differs on riscv32 -- the signal work itself is byte-identical to glibc on all four cross targets."
---

# waitpid on riscv32: -1/ENOSYS, with fork working

## The measurement

One probe, three targets, same crtl, same source:

```
                fork()     waitpid()   errno    status word
x86-64          1457296    1457296     0        0x00000700   (exit code 7)
arm32           1457627    1457627     0        0x00000700
riscv32         1457372    -1          38       0x5a5a5a5a   (never written)
```

The status word is pre-filled with `0x5A5A5A5A` on purpose, so "waitpid did not
write it" is visible rather than being read as a zero exit — **an expected value
that collided with the failure value would have made this row unable to fail**,
and 0 is exactly what an untouched-but-zeroed status would show.

arm32 and aarch64 pass under the SAME qemu-user, which is what rules out the
emulator: if `fork`/`wait4` were unsupported by qemu-user generally, they would
fail there too.

## Why the asymmetry is the expensive part

A refusal on `fork` would be honest and would stop the program at the top. Here
the fork SUCCEEDS — a real child exists — and only the reaping fails. So:

- the child becomes a zombie nobody can collect;
- the caller's `int status` keeps whatever it held, and `WIFEXITED(st)` /
  `WEXITSTATUS(st)` then report a **confident wrong answer** about a process
  that may have died any way at all;
- a caller that loops until `waitpid` returns the pid never terminates.

Any wait-based control flow is affected: a shell, an `init`, `system()`, and
busybox's whole run-an-applet path.

## Probable cause — NAMED AS UNCONFIRMED

rv32 is one of the Linux ports built without the legacy `wait4` syscall number
(the modern spelling is `waitid`). A PAL entry written against `wait4`'s number
therefore has nothing to call on that target and the kernel answers ENOSYS. This
has NOT been confirmed against `lib/rtl/platform/posix/platform_backend.pas`;
it is the first thing to check and it may be wrong.

## Repro

```c
#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <sys/wait.h>
int main(void){
  pid_t p, w; int st = 0x5A5A5A5A, e;
  p = fork();
  if (p == 0) { _exit(7); }
  errno = 0; w = waitpid(p, &st, 0); e = errno;
  printf("fork=%d wait=%d errno=%d status=0x%08x\n", (int)p, (int)w, e, (unsigned)st);
  return 0;
}
```

    ./compiler/pascal26 --target=riscv32 probe.c out && tools/run_target.sh riscv32 out

## Acceptance

The three-row table above, with riscv32 matching x86-64 and arm32. Assert the
RELATION — waitpid returns the pid it was given and writes a status the
WIFEXITED/WEXITSTATUS pair agrees with — never a per-target constant.

## What it currently blocks

`test/c_crtl_signal_dispositions.c` runs byte-identical to the gcc oracle on
x86-64, i386, arm32 and aarch64. Its riscv32 cross row is deliberately NOT
wired into `lib-test` and the Makefile names this slug as the reason, rather
than the row being quietly dropped: eight of its nine rows pass there and only
row 5, which watches a child die, cannot.
