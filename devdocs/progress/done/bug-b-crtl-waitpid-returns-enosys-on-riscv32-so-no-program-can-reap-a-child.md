---
slug: bug-b-crtl-waitpid-returns-enosys-on-riscv32-so-no-program-can-reap-a-child
title: "crtl waitpid() returns -1/ENOSYS on riscv32 while fork() works, so a child can be created and never reaped"
track: B
prio: 60
type: bug
status: done
created: 2026-09-04
found-by: franks-ab
owner: franks-ab
blocked-by: []
summary: "FIXED 2026-09-04. rv32 was the one target this repo builds for with NO wait4 at all: `platform_backend.pas` declared `SYS_wait4 = 260`, which is asm-generic's LEGACY number, unenabled on a 32-bit port -- so fork() returned a real child and waitpid() answered -1/ENOSYS and never wrote the caller's status word. `PalBackendWait4` now has a riscv32 arm over `waitid` (95) that rebuilds the packed status word from the siginfo, including the 0x7f/0xffff encodings for stopped, trapped and continued -- the arms an exit-code-only conversion gets wrong while every ordinary test still passes. The new `test/c_crtl_wait.c` stops and continues a child for exactly that reason, and it found a SECOND bug on the other four targets: `WIFSIGNALED` had been transcribed without glibc's `(signed char)` cast, so it answered TRUE with WTERMSIG 127 for every stopped or continued child on ALL FIVE targets, since the header was written. All twelve rows now byte-identical to the gcc oracle's own run on x86-64, i386, arm32, aarch64 and riscv32; `test/c_crtl_signal_dispositions.c` runs all nine rows on riscv32 and its cross row is wired in."
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

## Resolution (2026-09-04)

**The probable cause was right, and "wrong number" was the wrong word for it.**
`platform_backend.pas` declared `SYS_wait4 = 260` in the rv32 block. 260 is not
a mistranscription — it is the number asm-generic assigns `__NR_wait4` inside
its **legacy** block, which a 32-bit port does not enable. The declaration named
a syscall that does not exist on that target, and the kernel said so.

**Two instruments, and they fail differently.** This box's
`include/uapi/asm-generic/unistd.h` puts `wait4` behind the legacy guard (a
header read); `devdocs/dev/syscall-maps/riscv32.txt`, a qemu sweep rather than a
header read, has **nothing at 260** and **does** have `95 waitid`. Per-target
availability, wait4/waitid: i386 114/284, arm32 114/280, aarch64 260/95,
xtensa 121/122, **riscv32 —/95**. rv32 is the only target with waitid alone.

**The fix is a conversion, not a renumbering.** `PalBackendWait4` gains a
`{$ifdef CPU_RISCV32}` arm that calls `waitid` and rebuilds the packed wait4
status word from the siginfo: `CLD_EXITED -> status<<8`, `CLD_KILLED -> status`,
`CLD_DUMPED -> status|0x80`, `CLD_STOPPED`/`CLD_TRAPPED` -> `(status<<8)|0x7f`,
`CLD_CONTINUED -> 0xffff`. The siginfo buffer is zeroed first, which is
load-bearing and not tidiness: under WNOHANG with nothing ready the kernel
returns 0 and writes nothing, so `si_pid` must already be 0 for "nothing
happened" to be distinguishable from whatever was on the stack. `waitpid(0,...)`
resolves its own process group through `getpgid` rather than passing 0 to
`P_PGID`, which only acquired that meaning in Linux 5.4.

**The conversion is where such a fix goes wrong, and the exit-code rows cannot
see it.** An implementation that maps CLD_EXITED and CLD_KILLED and stops there
passes every ordinary test, because the common program forks, exits, and reads
`WIFEXITED`. `test/c_crtl_wait.c` therefore STOPS and CONTINUES a child.

### What the new test found on the other four targets

`WIFSIGNALED` was transcribed into `lib/crtl/include/sys/wait.h` **without
glibc's `(signed char)` cast**. For a stopped child the low 7 bits are 0x7f, so
`((s & 0x7f) + 1)` is 0x80; as a signed char that is -128 and `>>1` is -64, so
the macro is false. Without the cast it is 64 and `WIFSIGNALED` answered
**TRUE, with WTERMSIG 127**, for every stopped or continued child — on **all
five targets**, since the header was written. Nothing in the tree had ever
stopped a child. The header's own comment ("the MACROS here are real and
exact... they only decode an int the kernel already produced") was the thing
that was wrong, and it is now the measurement instead.

Positive control, measured: with the cast removed and nothing else changed, the
`stopped` and `continued` rows move to `signalled=1 sig=127` and no other row
does.

### Acceptance, measured

All twelve rows of `test/c_crtl_wait.c` byte-identical to the **gcc oracle's own
run** (not a literal — ECHILD's number and the stopped status word are the
kernel's, and hardcoding them would be the test asserting its own
implementation back at itself) on **x86-64, i386, arm32, aarch64 and riscv32**.
The return-value column asserts the RELATION `ret == the pid we passed`; no
per-target constant appears anywhere in the test.

`test/c_crtl_signal_dispositions.c` now runs all nine rows on riscv32 and its
cross row is wired into the Makefile loop, which is what this ticket blocked.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
