---
slug: bug-b-palnanosleep-answers-enosys-on-riscv32-because-rv32-has-no-nanosleep-syscall
track: B
prio: 45
type: bug
status: done
blocked-by: []
owner: unassigned
created: 2026-09-04
found-by: frankA (routing sysutils.Sleep through the PAL)
summary: "THE WHOLE PAL TIME FAMILY IS -ENOSYS ON riscv32, not just nanosleep — measured: PalNanosleep -38, PalRealtime -38 (sec=0), PalMonotonicMillis 0, while all four of x86-64, i386, aarch64 and arm32 answer correctly. One cause: rv32 never provided the 32-bit-time_t syscalls, and the posix backend hands it the asm-generic numbers (nanosleep 101, clock_gettime 113) that exist only on 64-bit asm-generic targets. rv32 needs the *_time64 calls (clock_nanosleep_time64 **407** -- this summary said 423 until it was fixed, and 423 is sched_rr_get_interval_time64, a wrong number that would have slept for nothing and returned a plausible 0; clock_gettime64 403) AND a 64-bit timespec — PalBackendNanosleep/Realtime build `array[0..1] of NativeInt`, which is 4-byte fields there, so the number alone is not the fix. Nothing observed it because every caller carried its own number table that omitted riscv32 and exited first; the silence had two layers and removing the outer one is what made this measurable."
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

## RESOLVED 2026-09-06 (frank-subcoord, Track B)

Fixed for the whole family, not one entry. `lib/rtl/platform/posix/platform_backend.pas`.

**One cause, and it needed BOTH halves.** rv32 is time64-only, so it needs the
`*_time64` numbers AND a 64-bit `__kernel_timespec`. Either half alone is
silently wrong: the right number with 32-bit fields makes the kernel read
tv_nsec out of the high half of tv_sec. So this landed as a define
(`PAL_TIME64`, riscv32 alone) plus ONE shared `TTimeSpec` whose field type is
`TPalTimeWord`, rather than as five edits.

**The struct was the real defect.** Nine call sites each built the timespec by
hand as `array[0..1] of NativeInt`, which is nine independent places to get the
width wrong; they are now one type. i386/arm32/xtensa keep native-width fields
(they are legacy-time32 and their kernels really do want 32-bit) — PAL_TIME64
carries the difference in one place.

**Numbers, corrected against the header.** clock_gettime64 403, clock_settime64
404, **clock_nanosleep_time64 407**, utimensat_time64 412, ppoll_time64 414,
rt_sigtimedwait_time64 421. THIS TICKET'S OWN SUMMARY SAID 423 AND 423 IS
`sched_rr_get_interval_time64` — issuing it would not have failed, it would have
slept for nothing and returned a plausible 0. Summary corrected above.
`clock_nanosleep` also takes the request THIRD, not first, so it is a different
CALL and not the same call at another number.

**Measured, all five targets, with a real positive control.** The control is the
change removed from the working tree (saved as a patch, `git checkout --`,
re-measured, re-applied), not `-Fu` at a pristine copy — `-Fu` does NOT override
the platform backend, and a control built that way PASSED on riscv32 while
measuring the fixed RTL. Caught by poisoning the pristine copy and watching the
build succeed anyway.

| call | rv32 before | rv32 after | x86_64/i386/aarch64/arm32 |
| --- | --- | --- | --- |
| PalNanosleep(300ms) | rc=-38, elapsed 0ms | rc=0, **elapsed 301ms** | unchanged, 300-304ms |
| PalClockGetTime | -38, sec=0 | 0, sec=1788721077 | unchanged |
| PalMonotonicMillis | 0 | 528704972 | unchanged |
| PalClockSetTime | -38 | **-1 (EPERM)** | -1 |
| PalPoll(400ms) | -38, 0ms | 0, **401ms** | 0, 400-402ms |
| PalSigTimedWait | -38 | -14 | -14 |
| PalUtimes | -38 | 0 | 0 |

`rc=0` alone could not have decided this — it is also what "returned instantly"
looks like — so every row above is timed or asserts an errno that DIFFERS from
the failure value. -1 (EPERM, refused) vs -38 (ENOSYS, absent) is the pair that
separates a correct number from a missing one.

**Gate:** `make lib-test` ok against stable v406 (skips synapse-ssl and
reportlab-diff, both prerequisite-absent, both unrelated). `tools/gate.sh quick`
green including the pinned-RTL canary and the FPC seed canary.

**Inert until pinned?** No. This is `lib/rtl`, read at compile time, so every
`$(PXX_STABLE)` consumer gets it on the next compile with no pin needed.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
