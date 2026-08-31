---
slug: bug-a-riscv32-sa-onstack-has-no-effect-under-qemu
track: A
prio: 12
type: bug
blocked-by: []
summary: "riscv32 registers a signal alt stack correctly — the sigaltstack syscall succeeds and the flags word assembles to $18000004 — but the handler still runs on the FAULTING stack under qemu-riscv32, so a stack-overflow SIGSEGV kills the process. The identical construction works under qemu-i386/arm/aarch64 of the same build, which points at qemu-user rather than at us. Unverifiable without hardware."
status: backlog
---

# riscv32: SA_ONSTACK is registered but has no effect under qemu

Residue from [[bug-a-four-hosted-targets-install-signal-handlers-without-an-altstack]],
which fixed i386, arm32 and aarch64. riscv32 got the same treatment and is the
one target where it does not take.

## Measured (2026-08-21, qemu 10.2.1, Debian 1:10.2.1+ds-1ubuntu3.1)

A handler that does nothing but `Halt(9)`, installed for SIGSEGV, against an
unbounded recursion:

| target | exit |
| --- | --- |
| i386 | 9 (handler ran) |
| arm32 | 9 |
| aarch64 | 9 |
| **riscv32** | **139 (killed; handler never entered)** |

And with an ordinary **nil deref** — a fault that leaves plenty of stack, so the
handler runs everywhere — printing where the handler's own frame lives:

| target | handler frame | main's frame |
| --- | --- | --- |
| i386 | 134636076 (the BSS alt stack) | 134642064 |
| arm32 | 134759292 (BSS) | 134764944 |
| aarch64 | 4364316 (BSS) | 4373824 |
| **riscv32** | **724215292 — 0x2AAAB..., the guest STACK** | 134784528 (BSS) |

So on riscv32 the handler runs on the normal stack even for a fault that has
nothing to do with stack space. SA_ONSTACK is simply not being honoured.

## Our side is correct, and that is verified rather than assumed

- `qemu-riscv32 -strace` shows `sigaltstack(0x8089550,(nil)) = 0` before each
  `rt_sigaction`. A zero return means ss_sp and ss_size reached the kernel
  intact — a bad size returns ENOMEM and a bad pointer EFAULT.
- The flags word was read back out of the emitted binary, not inferred: the
  install stub contains `lui t0, 0x18` (`0x000182B7`) immediately followed by
  `addi t0, t0, 4` (`0x00428293`), i.e. **$18000004** =
  SA_RESTART | SA_ONSTACK | SA_SIGINFO. Sole occurrence in the image.
- The struct layout matches the generic kernel `struct sigaction` for a
  no-SA_RESTORER arch on ILP32: handler at 0, flags at 4, mask at 8 — which is
  what the stub writes, and what already works for SA_SIGINFO on this target
  (`__pxxSigCode` / `__pxxSigContext` are green on riscv32).

## What is left to establish

The remaining variable is qemu-user's riscv signal-frame setup — whether it
picks the frame address with `target_sigsp()` (which honours SA_ONSTACK) or
straight from the CPU state. Same qemu build honours it on i386, arm and
aarch64, so this is riscv-specific there or riscv-specific here, and the
measurements above do not separate those two.

**It cannot be settled on this box**: there is no RISC-V hardware and no second
riscv emulator here. Settle it by (a) reading qemu's `linux-user/riscv/signal.c`
for the release in use, or (b) running the probe on real RV hardware. Until then
the registration stays — it is correct code asking for correct behaviour, not a
workaround, and it will start working the moment the other side does.

## Consequence today

`test_stack_overflow_raise` runs on four of five hosted targets. riscv32 is
excluded there with this ticket named, not silently skipped. Ordinary signal
handling on riscv32 is unaffected — only a fault that exhausts the stack is
unhandleable, which is exactly the case the alt stack exists for.

## Gate

The `Halt(9)` probe exiting 9 under riscv32, and `test_stack_overflow_raise`
promoted to all five targets.
