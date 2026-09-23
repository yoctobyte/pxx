---
slug: bug-b-terminalsize-answers-enotty-on-xtensa-and-the-probe-cannot-say-why
track: B
prio: 20
type: bug
blocked-by: []
owner: unassigned
created: 2026-09-04
found-by: frankA (routing ansiterm through the PAL)
summary: "SOLVED 2026-09-24 AND IT WAS NEITHER CANDIDATE. TerminalSize returned FALSE 80x24 on xtensa because ansiterm hardcoded the asm-generic TIOCGWINSZ $5413, and xtensa keeps the BSD-style 't' encoding for the window-size family while taking asm-generic for everything else. The correct value is $80087468 = _IOR('t',104,struct winsize) under LINUX's macro, and the DIRECTION BITS are the whole trap: Linux's _IOC_READ is 2 so _IOR sets $80000000 where BSD's sets $40000000. The original probe tried $40087468 -- the BSD spelling of the same idea -- so it was testing a constant that is WRONG UNDER BOTH HYPOTHESES IT WAS MEANT TO SEPARATE, which is exactly why it answered -25 like the generic one and refuted nothing. WHAT SEPARATED THEM was asking an ioctl of a fd where tty-ness cannot be the answer. Two rows did it and both are cheap: ioctl on a BAD FD (-1) answered -25 on xtensa where the kernel must answer -9 EBADF, because ioctl validates the fd before decoding the command -- so -25 on xtensa was never ENOTTY at all, it is what qemu-xtensa returns for a command not in its table, fd unexamined, and the probe's own positive control had been failing unnoticed; and TCGETS $5401 SUCCEEDED on fd 1, which only a real terminal does, refuting the no-tty candidate outright. qemu's -strace corroborated both, printing known commands BY NAME with a decoded termios (ICANON|ECHO, B38400 -- a live tty) and unknown ones as raw hex. FIXED in lib/rtl/ansiterm.pas behind {$ifdef CPU_XTENSA}, and in the two crtl C headers that carried the same constant, where TIOCSWINSZ $40087467 was measured the same way rather than derived. Measured at HEAD on all six targets in a pty: $5413 answers 0 on x86-64/i386/arm32/aarch64/riscv32 and -25 on xtensa, $80087468 the exact mirror; xtensa now reads TRUE 132x40 like every other target, and forcing the old constant back reproduces FALSE 80x24. THE XTENSA ROWS ARE QEMU-XTENSA, NOT SILICON -- qemu's table is derived from the kernel uapi rather than being an independent witness, though the accepted value is exactly the canonical encoding a kernel header generates. A run on real xtensa Linux would still be worth having and nothing here depends on it. Two side findings, both filed or fixed: <sys/ioctl.h> did not declare struct winsize (glibc's does; fixed, guarded), and the incomplete type that exposed compiled CLEAN with garbage member reads -- bug-c-an-undeclared-struct-type-compiles-and-reads-garbage. Also fixed: `#include <termios.h>` alone did not build at all, header declaring __pid_t while src/termios.c defined pid_t."
status: done
---

# xtensa TerminalSize: -ENOTTY, cause found 2026-09-24 (see the bottom)

Found while deleting ansiterm's four private per-target syscall number tables
and routing its five bodies through the PAL. The PAL has ioctl for all six
targets (xtensa 66), so the syscall now happens on xtensa where before the
number was simply absent.

## Measured, 2026-09-04

Same program, run under `script -qec 'stty rows 40 cols 132; ...'`:

| target | `PalIoctl(1, $5413, @ws)` | cols x rows |
| --- | --- | --- |
| x86-64 | 0 | 132 x 40 |
| i386, arm32, aarch64 | 0 | 132 x 40 |
| **riscv32** | **0** | **132 x 40** (was FALSE 80x24 before the PAL move) |
| **xtensa** | **-25** | 80 x 24 fallback |
| wasm32 | PAL_ERR_UNSUPPORTED | 80 x 24 fallback (wasi has no ioctl; correct) |

## WHY THIS TICKET IS ABOUT AN INSTRUMENT, NOT A NUMBER

The obvious hypothesis was that xtensa Linux uses the BSD-style ioctl command
encoding (`TIOCGWINSZ` = `$40087468`) rather than the generic `$5413`, the way
MIPS and SPARC do. It was tested rather than assumed, and the test refuted
nothing and confirmed nothing:

```
xtensa : generic $5413 rc=-25   bsd-style $40087468 rc=-25
x86-64 : generic $5413 rc=0     bsd-style $40087468 rc=-25
```

`-25` is `-ENOTTY`, and on x86-64 that is exactly what the WRONG constant
returns on a REAL tty. So on xtensa the two candidate causes produce the
identical observation and this probe cannot discriminate. The x86-64 row is what
makes that statement checkable rather than a shrug: it shows the probe CAN tell
a right constant from a wrong one when the tty is real, which is precisely why
its silence on xtensa is informative about the instrument.

## What would separate them

Something that answers about the tty rather than about the ioctl. Either:

- an ioctl xtensa should answer for a NON-tty fd as well (so a `-25` there means
  the constant, not the terminal), or
- `PalIsatty`/`TCGETS` on fd 0 AND fd 1 AND a plain file, three rows, so the
  pattern separates "this fd is not a terminal" from "this command is not
  recognised", or
- a run on real xtensa Linux hardware rather than qemu-xtensa.

Until one of those is done, do NOT copy an ioctl constant out of a header into
ansiterm and call it fixed -- a wrong syscall or command number does not fail
like a missing one, it calls something else, which is the exact reasoning that
kept the old private table empty for xtensa in the first place.

## Not a regression, and the reason matters

Before 2026-09-04 `GetSysIoctl` had no xtensa row, returned -1, and
`AnsiSetRawMode`/`TerminalSize` exited early -- the same 80x24 fallback. The
change moved xtensa from "refuses because nobody filled in a number" to
"asks and is told -ENOTTY". That is strictly more information and the same
behaviour, and it is why this is prio 20 rather than higher: no TUI drew
anything on xtensa before and none draws less now.


## 2026-09-24 — solved, and it was neither candidate (frankS)

The ticket asked for one of three things. The second one — *"`PalIsatty`/`TCGETS`
on fd 0 AND fd 1 AND a plain file, three rows, so the pattern separates 'this fd
is not a terminal' from 'this command is not recognised'"* — was the right
instinct, and the version that worked added a row nobody had thought of.

### The probe that separates them

| row | x86-64 | riscv32 | **xtensa** |
| --- | --- | --- | --- |
| **A** ioctl on a **bad fd** (-1), `$5413` | **-9** | **-9** | **-25** |
| B `FIONREAD $541B` on a **regular file** | 0 | 0 | -25 |
| C `FIONREAD` BSD-spelled, regular file | -25 | -25 | -25 |
| E `TIOCGWINSZ $5413` on fd 1 (pty) | 0 | 0 | -25 |
| **H** `TCGETS $5401` on fd 1 (pty) | 0 | 0 | **0** |

**Row A is the finding and it is about the instrument.** `ioctl()` validates the
fd *before* it decodes the command, so a bad fd must answer `EBADF`. x86-64 and
riscv32 do. xtensa answers `-25` — which the kernel cannot produce. **So `-25` on
xtensa was never `ENOTTY` at all.** It is what qemu-xtensa returns for a command
absent from its table, fd unexamined. The original probe's positive control had
been failing silently the whole time, and every `-25` read as evidence about a
terminal.

**Row H refutes the no-tty candidate outright.** `TCGETS` succeeds on fd 1, and
`TCGETS` succeeds only on a terminal. qemu's own `-strace` shows it decoded:

```
ioctl(1,TCGETS,...) = 0 ({c_iflag = ICRNL|IXON, c_cflag = B38400,CS8,CREAD,
                          c_lflag = ISIG|ICANON|ECHO|...})
```

A live tty's settings. Note qemu printed `TCGETS` **by name** and the unknown
commands as raw hex — the formatting itself distinguishes "in the table" from
"not in the table".

### The cause

xtensa keeps the BSD-style `'t'` encoding for the **window-size family** while
using asm-generic for everything else (`TCGETS $5401` and `TCSETS $5402` are the
generic numbers on xtensa too — measured, which is why only one constant is
conditional).

**The direction bits are the trap.** Linux's `_IOC_READ` is 2, so `_IOR` sets
`$80000000`; BSD's sets `$40000000`. `_IOR('t',104,struct winsize)` is therefore
`$80087468`. The 2026-09-04 probe tried **`$40087468`** — the BSD spelling — so
it tested a constant that is wrong under *both* hypotheses it was meant to
separate. That is the whole reason it "refuted nothing and confirmed nothing".

```
xtensa, in a 132x40 pty:
  generic   $5413     rc=-25
  bsd-dir   $40087468 rc=-25     <- what the old probe tried
  linux_IOR $80087468 rc=0 rows=40 cols=132
```

### Fixed

`lib/rtl/ansiterm.pas` behind `{$ifdef CPU_XTENSA}`, and both crtl C headers
that carried the same constant. `TIOCSWINSZ $40087467` was **measured** (read
the size, write it back) rather than derived from the same macro.

Verified at HEAD, all six targets, each in a pty: xtensa now reads
`TRUE 132x40` like everything else, and forcing the old constant back reproduces
`FALSE 80x24`. The Makefile's `atpal` recipe gains an **xtensa pty row**, and its
comment — which stated this ticket's old uncertainty — is retired. The existing
x86-64 pty row is that row's control: a missing pty makes a *correct* constant
answer `FALSE 80x24`, so both red means the harness lost its pty and xtensa alone
red means the constant regressed.

### The caveat that remains

**Every xtensa row here is qemu-xtensa, not silicon.** qemu's target ioctl table
is derived from the kernel's uapi headers, so it is not an independent witness.
What raises it above "qemu says so" is that the accepted value is exactly the
canonical `_IOR('t',104,8)` a kernel header generates, and that qemu decoded and
named the request. The third option in "What would separate them" — a run on real
xtensa Linux — is still worth having. Nothing here depends on it.

### Two side findings

- **`<sys/ioctl.h>` did not declare `struct winsize`** though glibc's does, so
  the canonical `#include <sys/ioctl.h>` + `struct winsize ws;` got an incomplete
  type. Fixed, guarded by `__struct_winsize_defined` in both headers.
- **That incomplete type compiled CLEAN** and read garbage — `cols=8650792`,
  which is `0x00840028`, the correct 132 and 40 read as one 32-bit field, with
  `rc=0` from a genuinely successful syscall. Filed as
  `bug-c-an-undeclared-struct-type-compiles-and-reads-garbage`. It briefly looked
  like the new constant being wrong on *both* targets; a two-short control struct
  separated them.
- **`#include <termios.h>` alone did not build at all** — the header declares
  `__pid_t tcgetsid` while `src/termios.c` defines `pid_t tcgetsid`, and nothing
  it included provided the unprefixed name. Fixed with `#include <sys/types.h>`
  in the implementation file, where the namespace restriction does not apply.

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
