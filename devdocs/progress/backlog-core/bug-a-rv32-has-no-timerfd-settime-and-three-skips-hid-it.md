---
slug: bug-a-rv32-has-no-timerfd-settime-and-three-skips-hid-it
title: "riscv32 CoSleep hangs forever — timerfd_settime(86) is ENOSYS there, and the skip that hid it also hid two rows that already passed"
track: A
prio: 65
type: bug
status: open
owner: frank-subcoord
created: 2026-09-06
found-by: frank-subcoord (widening the 32-bit-time_t group after 677e75495)
summary: "FIX IS WRITTEN, VERIFIED, AND PARKED as devdocs/progress/patches/rv32-timerfd-time64-and-three-unskips.patch — held only for the landing quiet period, land it when the tier reports. rv32 is time64-only, so scheduler.pas's timerfd_settime(86) answers -38 ENOSYS and ArmOneShotTimer DISCARDS the rc, returning a valid fd for a timer that was never armed: test/test_timer.pas hangs forever on riscv32 (rc=124, no output) while x86-64 prints woke 50/100/150/done. Fourth instance of the class fixed in 677e75495, and the first that is a HANG rather than a wrong value. The row was invisible because the Makefile SKIPPED it as 'backend feature gap' — a reason true when written and stale since rv32 coroutines landed; two sibling skips under the same stale reason (test_reactor, test_asyncecho) PASS today and passed before this fix, so they were pure lost coverage. The two extern_c skips are real and stay."
---

# rv32 has no timerfd_settime, and the skip was hiding a hang

## Measured (this box, qemu-riscv32)

Direct probe — the same fd, two numbers:

```
timerfd_create(85)     = 3        { takes no timespec, works }
timerfd_settime(86)    = -38      { ENOSYS: rv32 never got the time32 calls }
timerfd_settime64(411) = 0
```

`test/test_timer.pas`, built by `compiler/pascal26`:

| target | before | after |
| --- | --- | --- |
| x86-64 / i386 / aarch64 / arm32 | `woke 50 / woke 100 / woke 150 / done` | unchanged |
| riscv32 | **rc=124, NO OUTPUT — hangs forever** | `woke 50 / woke 100 / woke 150 / done` |

## Why it hangs rather than fails

`ArmOneShotTimer` assigns the syscall result to `rc` and never reads it. So the
ENOSYS is discarded, the function returns a perfectly valid timerfd, and
`CoSleep` parks on `WaitReadable(tfd)` for a timer that was never armed. Nothing
in the path can observe the failure. `WaitIOTimeout` has the same shape, so a
timeout on rv32 never fires either.

## Two defects, not one — the struct as well as the number

`timerfd_settime64` wants a 64-bit `itimerspec`, so `it_value` starts at +16,
not +8. The existing code selects that layout on `{$ifdef CPU64}`, and rv32 is
a 32-bit machine with a 64-bit timespec — the one combination `CPU64` cannot
express. The patch adds `SCHED_TIME64` (riscv32 alone), mirroring `PAL_TIME64`
in `platform_backend.pas`, and writes the fields through an explicit `^Int64`
rather than relying on `spec` having been cleared.

## THE SKIP IS THE REAL FINDING

`Makefile` carried five riscv32 skips, all reading
`backend feature gap (see bug-test-riscv32-thin-coverage notes)`. Measured, they
are three different things:

| row | truth today | before this fix |
| --- | --- | --- |
| `test_timer` | **was a live HANG** | hung — a red the skip hid |
| `test_reactor` | passes | **already passed** — pure lost coverage |
| `test_asyncecho` | passes | **already passed** — pure lost coverage |
| `test_extern_c` | genuinely refused | real skip, keep |
| `test_extern_c_float` | genuinely refused | real skip, keep |

The reason was TRUE for all five when written and stopped being true for three
of them at different moments — and because **a skip is silent**, nothing said
so. The two extern_c rows refuse loudly with a diagnostic
(`external (dynamic) symbols are not supported on this target`), which is what
a correct skip looks like: it names a reason you can re-test cheaply.

frankZ's rule, arrived at independently the same evening: **a false skip is
worse than a false red.** A red is loud. This one cost a hang on a target the
release advertises, plus two rows of coverage nobody knew were missing.

## Land

`devdocs/progress/patches/rv32-timerfd-time64-and-three-unskips.patch` —
`lib/rtl/scheduler.pas` + the three Makefile rows, with the un-skip comment
explaining which reasons were stale and which are real. All three rows verified
through `tools/expect_same.sh` exactly as the Makefile invokes them, with a
negative control (a wrong expectation gives `MISMATCH`, rc=1).

Held ONLY for the bounded landing quiet period. This is a red fix, not tidiness.
