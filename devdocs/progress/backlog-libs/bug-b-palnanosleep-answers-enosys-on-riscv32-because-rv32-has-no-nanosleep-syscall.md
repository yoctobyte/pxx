---
slug: bug-b-palnanosleep-answers-enosys-on-riscv32-because-rv32-has-no-nanosleep-syscall
track: B
prio: 45
type: bug
status: open
blocked-by: []
owner: unassigned
created: 2026-09-04
found-by: frankA (routing sysutils.Sleep through the PAL)
summary: "THE WHOLE PAL TIME FAMILY IS -ENOSYS ON riscv32, not just nanosleep — measured: PalNanosleep -38, PalRealtime -38 (sec=0), PalMonotonicMillis 0, while all four of x86-64, i386, aarch64 and arm32 answer correctly. One cause: rv32 never provided the 32-bit-time_t syscalls, and the posix backend hands it the asm-generic numbers (nanosleep 101, clock_gettime 113) that exist only on 64-bit asm-generic targets. rv32 needs the *_time64 calls (clock_nanosleep_time64 423, clock_gettime64 403) AND a 64-bit timespec — PalBackendNanosleep/Realtime build `array[0..1] of NativeInt`, which is 4-byte fields there, so the number alone is not the fix. Nothing observed it because every caller carried its own number table that omitted riscv32 and exited first; the silence had two layers and removing the outer one is what made this measurable."
---

# PalNanosleep is -ENOSYS on riscv32

## Measured

```pascal
program nsl;
uses platform;
begin WriteLn('PalNanosleep(0,300000000) = ', PalNanosleep(0, 300000000)); end.
```

| target | result |
| --- | --- |
| x86-64, i386, aarch64, arm32 | `0` |
| riscv32 | `-38` (-ENOSYS) |

And the observable, `Sleep(300)` timed with `Now`: TRUE on x86-64, i386,
aarch64, arm32 and xtensa; FALSE on riscv32 — **and FALSE on riscv32 before the
sysutils change too**, measured by restoring the old file and recompiling (the
RTL is read at compile time, so no rebuild is needed for that control).

## Cause

`lib/rtl/platform/posix/platform_backend.pas` gives riscv32 `SYS_nanosleep = 101`
out of the asm-generic table, alongside aarch64's identical 101. That number is
right for a 64-bit asm-generic target and wrong for **rv32**: the 32-bit-time_t
syscalls were not provided there, and userspace is expected to use
`clock_nanosleep_time64` (423) with a 64-bit `timespec` — two `Int64` fields, not
two `NativeInt`.

`PalBackendNanosleep` builds `ts: array[0..1] of NativeInt`, which is 4-byte
fields on rv32, so even with the right number the struct would be wrong.

## Why nobody saw it

`sysutils.Sleep` used to carry its own four-arm nanosleep number table —
x86-64, i386, aarch64, arm32 — with **no riscv32 arm at all**, so it took
`if n = -1 then Exit` and never reached the PAL. Two independent silences
stacked: a missing arm in the duplicate table, and a wrong number in the real
one. Deleting the duplicate did not cause this; it made it reachable, which is
the only reason it is a measurement rather than a guess.

Same family as
`bug-b-ansiterm-has-no-syscall-numbers-for-riscv32-or-xtensa-so-every-tui-draws-nothing`:
a private copy of the syscall table missing exactly riscv32, failing softly, and
the `-1` guard swallowing the evidence.

## What a fix has to do

Not just swap 101 for 423. rv32 needs the **time64** shape: a 64-bit timespec and
`clock_nanosleep(CLOCK_MONOTONIC, 0, &ts, NULL)` argument order (clockid, flags,
req, rem), which is a different call signature from `nanosleep(req, rem)` — so
either a riscv32 arm inside `PalBackendNanosleep` or a per-arch spelling, not a
number-table edit.

Positive control: the four targets above must still answer 0 and
`Sleep(300)` must still measure >= 250ms on each. A fix that changes the shared
path and is only run on riscv32 cannot see that it broke them.

## THE FAMILY, measured 2026-09-04 after the sysutils change

```pascal
program clk;
uses platform;
var sec, nsec: Int64;
begin
  WriteLn('PalRealtime rc=', PalRealtime(sec, nsec), ' sec=', sec);
  WriteLn('PalMonotonicMillis=', PalMonotonicMillis);
end.
```

| target | PalNanosleep | PalRealtime | PalMonotonicMillis |
| --- | --- | --- | --- |
| x86-64 | 0 | rc 0, sec 1788525344 | 332972432 |
| i386 | 0 | rc 0, plausible | non-zero |
| aarch64 | 0 | rc 0, plausible | non-zero |
| arm32 | 0 | rc 0, plausible | non-zero |
| **riscv32** | **-38** | **rc -38, sec 0** | **0** |

**One cause, three entries** — which is what makes it a mechanism rather than
three bugs: rv32 has none of the 32-bit-time_t syscalls, and the posix backend
gives it the asm-generic numbers that only exist on 64-bit asm-generic targets.

`PalMonotonicMillis` returning **0** rather than an error is the one to watch:
a caller measuring an interval gets `0 - 0 = 0` elapsed and no failure signal at
all, so any timing or timeout loop on riscv32 spins or completes instantly.

Same pattern was in a THIRD private table, and it has since been removed:
`pxxcio.pas`'s `SysClockGettimeNr` omitted riscv32 *on purpose*, with the comment
"no lua/sqlite test exercises time on it, so it falls through to the 0 stub
rather than risking the rv32 time64 ABI". That comment was correct about the
risk and it is what had been hiding this — the duplicate table is the reason the
real one was never asked.

## THE OUTER LAYER IS GONE AS OF 2026-09-04, so this is now REACHABLE from C

`pxxcio.pas`'s three clock bodies and its exit body now go through
`PalClockGetTime` / `PalExit`; the private tables are deleted. Nothing changed
for riscv32 — it answered 0/-1 through the local stub and answers 0/-1 through
the PAL, measured identically before and after on the same probe — but the
answer is now produced by the code this ticket is about, so fixing the PAL fixes
C too.

`test/c_cross_time_and_exit_through_the_pal.c` is wired for i386, aarch64, arm32
and riscv32 and **asserts riscv32's hole rather than tolerating it**: argv[1] is
whether the target is expected to have a working clock, the Makefile passes `0`
for riscv32 and `1` for the rest, and each target also runs a must-fail control
with the opposite expectation. When this ticket is fixed, that row must be
changed to `1` — and until it is, the riscv32 arm will start FAILING, which is
the intended way for this ticket to announce its own resolution.
