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
summary: "PalNanosleep returns -38 (-ENOSYS) on riscv32 and 0 on x86-64, i386, aarch64 and arm32 — measured, one line each. The posix backend gives riscv32 SYS_nanosleep = 101 from the asm-generic table, and rv32 does not HAVE 101: the 32-bit-time_t syscalls were never provided on rv32, which uses clock_nanosleep_time64 (423) with a 64-bit timespec. So Sleep does not sleep on riscv32 and never has; nothing observed it because sysutils carried its own number table with no riscv32 arm and exited before calling the PAL at all. The silence had TWO layers, and removing the outer one is what made the inner one measurable."
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
