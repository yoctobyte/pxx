---
slug: bug-b-terminalsize-answers-enotty-on-xtensa-and-the-probe-cannot-say-why
track: B
prio: 20
type: bug
blocked-by: []
owner: unassigned
created: 2026-09-04
found-by: frankA (routing ansiterm through the PAL)
summary: "TerminalSize returns FALSE 80x24 on xtensa under qemu-xtensa even inside a pty that every other target reads as 132x40, because PalIoctl(1, TIOCGWINSZ) answers -25 (-ENOTTY). TWO CANDIDATE CAUSES AND THIS PROBE CANNOT SEPARATE THEM: xtensa Linux may use BSD-style ioctl command encodings rather than the $5401/$5402/$5413 generic ones ansiterm hardcodes, or qemu-xtensa may simply not present fd 1 as a tty. Measured: BOTH the generic $5413 and the BSD-style $40087468 give -25 on xtensa, while on x86-64 in the same pty the first gives 0/132x40 and the second gives -25 -- so -25 is exactly what a wrong constant looks like AND what no-tty looks like. Not a regression: xtensa had no ioctl syscall number at all before 2026-09-04 and took the same 80x24 fallback."
---

# xtensa TerminalSize: -ENOTTY, cause undetermined

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
