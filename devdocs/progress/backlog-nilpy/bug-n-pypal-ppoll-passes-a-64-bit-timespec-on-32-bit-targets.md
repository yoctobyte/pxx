---
slug: bug-n-pypal-ppoll-passes-a-64-bit-timespec-on-32-bit-targets
title: "PyPalPoll passes a 64-bit TPyPalTimespec to ppoll on i386/arm32, which expect a 32-bit one"
track: N
type: bug
prio: 35
status: open
found: 2026-08-29
found-by: claude-N
---

# The timeout struct is 64-bit on every target; ppoll's is not

`TPyPalTimespec` is two `Int64` fields, and `PyPalPoll` hands its address to
`ppoll`:

```pascal
r := __pxxrawsyscall(NR_PPOLL, Int64(@pfd), 1, Int64(tsp), 0, 8, 0);
```

That is correct on the 64-bit targets, where `struct timespec` is two 64-bit
words. On **i386 (309) and arm32 (336)** the legacy `ppoll` takes a **32-bit**
`timespec` — two 32-bit words — so the kernel reads `tv_sec` from the low half
of our first field and `tv_nsec` from its HIGH half, which is zero.

Consequence on those two targets: a timeout of N milliseconds is read as
N/1000 seconds and 0 nanoseconds only when N is a whole number of seconds, and
as a **zero nanosecond field with a garbage-free but wrong seconds value**
otherwise — i.e. sub-second timeouts silently become 0 (a poll that returns
immediately) and the nanosecond half never arrives.

## Not introduced by the clock work, but adjacent to it

Found on 2026-08-29 while adding `NR_CLOCK_GETTIME`, which uses the SAME record
and is correct precisely because it uses `clock_gettime64` on the 32-bit
targets — whose `__kernel_timespec` really is two 64-bit fields. `ppoll` has no
such automatic fix available: the time64 spelling is `ppoll_time64` (414), a
different syscall number.

So the record is right for one caller and wrong for the other, which is why
this was invisible: one struct serving two ABIs.

## Options

**A.** Use `ppoll_time64` (414) on the 32-bit targets, exactly as
`clock_gettime64` (403) is used for the clock. Keeps one struct, one layout,
y2038-clean. Same uniform-time64-block reasoning, and 414 is verifiable from
the generic `syscall.tbl`.

**B.** A separate 32-bit timespec record used only by `ppoll` on those targets.
More code and reintroduces the per-arch layout the clock work just removed.

**A** is recommended and is roughly the same shape as the change that exposed
this.

## Reachability

Only through `select.select` / the stdin poll path, and only on i386/arm32.
**Not observed failing** — nothing in the current test matrix polls with a
sub-second timeout on a 32-bit target, which is exactly why it is filed rather
than fixed blind: the fix needs a 32-bit run to confirm, and this box cannot
execute one.

## Gate

A `.npy` polling stdin with a sub-second timeout, cross-compiled for i386 and
run under qemu, before and after.
