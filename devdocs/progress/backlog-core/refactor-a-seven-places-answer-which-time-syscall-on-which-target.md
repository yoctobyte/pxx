---
slug: refactor-a-seven-places-answer-which-time-syscall-on-which-target
title: "Seven sites independently encode 'which time syscall on which target', and the four with their own table are the four that broke"
track: A
prio: 45
type: refactor
status: open
owner: unassigned
created: 2026-09-06
found-by: frank-subcoord (census after fixing three of them)
summary: "A CENSUS, not a proposal: seven sites in this tree independently answer 'which clock/timer syscall number, and how wide is its timespec, on this target'. THREE WERE WRONG AND ONE OF THOSE HUNG — all three had their own local number table. The one site that routes through the PAL instead (pxxcio) was fixed for free by fixing the PAL and needed no edit. The rule they each rediscover is one sentence: riscv32 is time64-only, so it needs the *_time64 number AND a 64-bit timespec on a 32-bit machine, while i386/arm32/xtensa are the opposite. Three of the seven genuinely CANNOT route through the PAL (palfutex, palpthread and builtin.pas are below or beside it by design), so the fix is not 'make everything call the PAL' — it is to stop the rule being folklore. Not urgent: nothing is known-broken today after this evening's fixes. Filed so the eighth site does not rediscover it by hanging."
---

# Seven answers to one question

Measured 2026-09-06 while fixing the 32-bit-`time_t` group (677e75495 plus the
scheduler fix). Every site below decides, per target, a syscall number and a
timespec width. They do not share a table.

| # | site | state found | how it broke, or why not |
| --- | --- | --- | --- |
| 1 | `lib/rtl/platform/posix/platform_backend.pas` | **BROKEN** | whole rv32 time family -38 ENOSYS; nine hand-rolled timespecs. Fixed + normalised to one `TTimeSpec`. |
| 2 | `compiler/builtin/pypal.pas` | **HALF BROKEN** | clock used 403 correctly; ppoll kept the legacy number against a 64-bit record, so sub-second timeouts returned instantly on i386/arm32. Fixed. |
| 3 | `lib/rtl/palfutex.pas` | correct | already had `futex_time64` 422 and an rv32-only 64-bit timespec. Someone hit this rule here first and solved it locally. |
| 4 | `lib/rtl/scheduler.pas` | **BROKEN — a HANG** | `timerfd_settime(86)` is ENOSYS on rv32 and the rc was discarded, so `CoSleep` parked forever on a timer never armed. Picked its struct layout off `CPU64`, which cannot express "32-bit machine, 64-bit timespec". |
| 5 | `lib/rtl/palpthread.pas` | 0-stubbed | rv32 simply absent from its number list, so monotonic time was 0. Unreachable today (`--threadsafe` refuses on rv32); fixed anyway as a landmine. |
| 6 | `compiler/builtin/builtin.pas` | correct | already 403 with a 64-bit buffer. |
| 7 | `lib/rtl/pxxcio.pas` | correct **by construction** | carries no table — routes through `PalClockGetTime`. Fixing #1 fixed C's `clock_gettime` and `time()` on rv32 with **no edit to this file**: measured rc=-1/sec=0 before, correct after. |

## What the table says

The three that broke are three of the four that keep their own numbers. The one
that keeps none was fixed by fixing something else. That is the whole finding,
and `devdocs/dev/root-cause-over-microfix.md`'s counting rule calls two a smell
and three a design flaw — this is seven.

## What the fix is NOT

"Route everything through the PAL" is wrong and would be rejected. #3, #5 and #6
are deliberately below or beside the PAL: `palfutex` depends on nothing,
`palpthread` is pulled into C compiles under `--threadsafe` and keeps its
dependencies minimal, and `builtin.pas` is a compiler builtin that cannot use
`lib/rtl` at all. Their locality is a design decision, not an oversight.

## What it might be

The rule each site rediscovers is one sentence, and the cost is that it is
FOLKLORE rather than a thing you can be handed:

> riscv32 is time64-only: every timespec-taking syscall needs its `*_time64`
> number AND a 64-bit `__kernel_timespec`, on a 32-bit machine. i386, arm32 and
> xtensa are the opposite — legacy numbers, native-width fields. Selecting on
> `CPU64` is always wrong; the axis is the target's time ABI, not its word size.

Options, in rough order of appeal:
1. A shared include (`{$I time64.inc}`) defining `PAL_TIME64` / `TPalTimeWord`
   that even the dependency-free units can `{$I}` without a `uses` — the one
   mechanism that respects why #3/#5/#6 are standalone.
2. Leave the code alone and add a **test** that every target answers a real
   errno rather than -38 for each timespec syscall the tree issues. Cheaper,
   catches the eighth site, changes no layering.
3. Nothing, and accept a rediscovery every time a target is added.

Recommend 2 first — it is the one that would have caught #4, which nothing did
for as long as the row that would have failed was skipped
(`bug-a-rv32-has-no-timerfd-settime-and-three-skips-hid-it`).

**No urgency.** Nothing here is known-broken after the fixes above. This is
filed so that the eighth site is found by a test instead of by a hang.
