---
slug: bug-a-xtensa-tkill-syscall-number-is-unlocated
track: A+S
prio: 25
type: bug
status: done
blocked-by: []
created: 2026-09-05
resolved: 2026-09-23
owner: frank
commit: 9a701a66d2
found-by: frankS (settling the xtensa getpid/gettid set)
summary: "SETTLED 2026-09-23: xtensa `SYS_tkill = 124` (and `gettid = 127`, already known). IT WAS IN THE ABANDONED 118-136 RANGE, AND THE RANGE EXPLAINS ITS OWN ABANDONMENT -- 118 is `exit` and 119 is `exit_group`, so an in-process sweep starting at 118 calls exit(0) on its FIRST iteration and terminates with nothing traced, which is exactly the reported symptom. The conclusion (something there ends the program) was right; the inference that the range could not be probed was not. What changed is the INSTRUMENT, not the range: ONE SYSCALL PER PROCESS, a technique already recorded in the coswitch ticket and simply not applied here -- per process, a number that kills the probe costs its own row and nothing after it. Confirmed by two instruments that fail differently: qemu -strace names 124 `tkill`, and functionally tkill(gettid(),0)=0 while tkill(999999,0)=-1 ESRCH, which a wrong number cannot both do. Controls 120/126/127/150/224 all reproduce the tree`s settled numbers. test_signal_num, test_signal_siginfo and test_signal_bss_alias gain a CPUXTENSA arm and NOW BUILD for xtensa, with x86-64 and riscv32 verified unchanged. THEY STILL DO NOT RUN and that residual is owned, not buried: all three deliver the signal and run the handler, then SIGILL downstream on bug-a-xtensa-emits-muluh-for-an-integer-multiply-and-no-stock-qemu-core-implements-it, so they are deliberately NOT wired into the suite for xtensa -- doing so would add three red rows for a cause unrelated to signals."
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

---

# SETTLED 2026-09-23 (frank) — `SYS_tkill = 124`

## The number

| number | name |
| --- | --- |
| 118 | `exit` |
| 119 | `exit_group` |
| 120 | `getpid` |
| 121 | `wait4` |
| 122 | `waitid` |
| 123 | `kill` |
| **124** | **`tkill`** |
| 125 | `tgkill` |
| 126 | `set_tid_address` |
| 127 | `gettid` |
| 128 | `setsid` |
| 129 | `getsid` |
| 130 | `prctl` |

**It was in the abandoned range all along, and the range explains its own
abandonment: 118 is `exit` and 119 is `exit_group`.** An in-process sweep
starting at 118 calls `exit(0)` on its FIRST iteration and terminates with
nothing traced — which is precisely the reported *"made the process exit(0)
immediately with none of the loop's calls traced"*. The conclusion drawn was
"something in that range has a side effect that ends the program", which was
correct, and the inference that the range could not be probed was not.

## What changed is the instrument, not the range: ONE SYSCALL PER PROCESS

The technique was already in this tree — the xtensa column of
[[feature-a-coswitch-for-xtensa-and-riscv32-the-scheduler-has-no-context-switch-there]]
records its numbers as measured *"one syscall per process under qemu-xtensa
-strace"*. It was simply not applied here. Per process, a number that kills the
probe costs **its own row and nothing after it**, so `exit` and `exit_group`
stop being a hazard and become two data points.

A single binary reading the number from `argv` would be neater and does **not
work**: it SIGILLs on xtensa before reaching the syscall. Bake the constant and
compile one program per number. (The SIGILL is the same one filed as
[[bug-a-xtensa-emits-muluh-for-an-integer-multiply-and-no-stock-qemu-core-implements-it]] —
`ParamStr` + string-to-integer multiplies.)

## Two instruments that fail differently

1. **qemu's own name table**, via `-strace`: `124` prints as `tkill`.
2. **Functional**: `tkill(gettid(), 0) = 0`, and `tkill(999999, 0) = -1 errno=3
   (No such process)`. Signal 0 is an existence check and sends nothing.

The second is what makes it more than a table lookup: a wrong number cannot
return 0 for a live tid *and* ESRCH for a bogus one.

**Controls — every number this ticket already considered settled reproduces:**
`120 getpid`, `126 set_tid_address`, `127 gettid`, `150 getppid`,
`224 sigaltstack`. The ticket's warning holds and is worth keeping: `224` is
`sigaltstack` here where it is `gettid` on ARM/i386, and `130` is `prctl` where
asm-generic puts `tkill` — so copying either arm calls a real but wrong syscall
and gets a plausible return.

## Landed

`test_signal_num.pas`, `test_signal_siginfo.pas` and `test_signal_bss_alias.pas`
each gain a `CPUXTENSA` arm with the measurement recorded beside it. All three
**now build for xtensa**, which was this ticket's stated defect. Verified no
regression: all three still build and run identically on x86-64 and riscv32
(the inserted `{$endif}`/`{$ifdef}` pair is nesting-correct).

## THEY STILL DO NOT RUN, AND THAT IS NOT THIS TICKET — but it has an owner

All three get as far as printing their prefix (`usr1=`, `segv code=`, `hit=`)
and then SIGILL. **The signal is delivered and the handler runs**; the fault is
downstream of everything they test, and it reproduces in three lines with no
signals involved. Filed as
[[bug-a-xtensa-emits-muluh-for-an-integer-multiply-and-no-stock-qemu-core-implements-it]]:
the backend emits `muluh` (MUL32_HIGH) for an integer multiply and no stock
qemu-xtensa core implements it, so hosted xtensa cannot print a number.

**The three are deliberately NOT wired into the suite for xtensa.** Wiring them
would add three red rows for a cause unrelated to signals. That is the condition
to revisit when the `muluh` ticket closes — they are its named positive-control
population.

## Log
- 2026-09-23 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 9a701a66d2.
