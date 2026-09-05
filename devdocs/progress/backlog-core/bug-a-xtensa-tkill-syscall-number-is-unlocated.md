---
slug: bug-a-xtensa-tkill-syscall-number-is-unlocated
track: A+S
prio: 25
type: bug
status: open
blocked-by: []
created: 2026-09-05
found-by: frankS (settling the xtensa getpid/gettid set)
summary: "xtensa's SYS_tkill number is not known, so test_signal_siginfo.pas and test_signal_num.pas still have no xtensa arm and do not build for that target. gettid IS settled (127, by qemu -strace, calibrated against getppid=150), and 224 is sigaltstack on xtensa -- NOT gettid as it is on ARM and i386 -- so copying either of those arms would call the wrong syscall and get a plausible return. tkill is not in 205-215, 227-252, and a blind (0,0) sweep of 118-136 terminated the process without tracing, so that range was abandoned rather than pushed through. Needs a non-sweep source."
---

# xtensa's tkill syscall number is unlocated

## What IS settled, so nobody re-does it

`qemu-xtensa -strace` names each call from the emulator's own xtensa syscall
table. Calibrated first against the row the tree already considered settled —
150 came back `getppid` and returned the parent pid — then applied:

| number | name |
| --- | --- |
| 120 | `getpid` |
| 126 | `set_tid_address` |
| 127 | **`gettid`** |
| 150 | `getppid` (calibration) |
| 224 | **`sigaltstack`** |

That collapses the `120/126/127` set recorded in `ir_codegen_xtensa.inc`, which
had asked for a threaded measurement — **unbuildable here**, because
`{$threadsafe on}` is x86-64/i386/aarch64/arm32 only, so xtensa cannot create a
second thread to ask from.

## What is not settled

`SYS_tkill`. Searched: **205–215** (nfsservctl … sched_getscheduler),
**227–252** (rt_sig* … timer_getoverrun, plus `Unknown syscall 238`). Not
present in either.

**The 118–136 sweep was abandoned, deliberately.** Probing it with `(0, 0)` args
made the process `exit(0)` immediately with none of the loop's calls traced — so
something in that range has a side effect that ends the program, and continuing
to blind-fire into syscalls that do that is not a measurement, it is a hazard.
The three-number question above was already answered; this one did not justify
the risk.

**A non-sweep source is what this needs** — qemu's `linux-user/xtensa`
syscall table, or the kernel's `arch/xtensa/include/uapi/asm/unistd.h` — read
rather than executed, then confirmed with a single targeted `-strace` call at
`sig=0`. That is one lookup and one call, and it fails differently from a sweep.

## Why it matters, and how little

`test_signal_siginfo.pas` and `test_signal_num.pas` carry `{$ifdef CPU…}` blocks
defining `SYS_gettid`/`SYS_tkill` and have no xtensa arm, so neither builds for
xtensa. Both use `tkill(gettid(), sig)` specifically because it produces
`SI_TKILL`, which the tests assert — `kill(getpid(), sig)` would give `SI_USER`
and is not a substitute.

Prio 25 because the signal *runtime* on xtensa is otherwise covered: fault-to-
raise, the SP rewrite and stack-overflow-to-exception all run there and match
x86-64 byte for byte (see feature-a-xtensa-ucontext-pc-sp-offsets). This is two
test arms, not a capability gap.

## The trap, left written down

**Do not copy the ARM or i386 arm.** Both define `SYS_gettid = 224`, and on
xtensa 224 is `sigaltstack` — it would return plausibly rather than fail, which
is the failure mode that gets a wrong number believed.
