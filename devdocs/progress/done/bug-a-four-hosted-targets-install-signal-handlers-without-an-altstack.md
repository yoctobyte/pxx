---
slug: bug-a-four-hosted-targets-install-signal-handlers-without-an-altstack
track: A
prio: 40
status: done
owner: claude-A
---

# Four hosted targets install signal handlers without an altstack, so a stack overflow kills them outright

x86-64's `EmitSignalRuntime` allocates `BSS_SIG_ALTSTK`, calls `sigaltstack(2)`
and passes `SA_ONSTACK` (`ir_codegen.inc:508`, flags `$1C000004`). The other four
hosted targets — i386, arm32, aarch64, riscv32 — install with `SA_SIGINFO` but
**no** `SA_ONSTACK` and no `sigaltstack` call.

The consequence is not a degraded handler, it is no handler:

```pascal
procedure OnSegv; begin WriteLn('segv hit ', hits); Halt(7); end;
...
SetSignalHandler(11, @OnSegv);
Recurse;                        { unbounded, 2KB frames }
```

| target | result |
| --- | --- |
| x86-64 | `segv hit 1 depth=4059`, exit 7 |
| aarch64 | `qemu: uncaught target signal 11`, exit 139 |
| arm32 | `qemu: uncaught target signal 11`, exit 139 |
| i386 | `Segmentation fault (core dumped)`, exit 139 |
| riscv32 | killed, exit 139 |

(measured 2026-08-21, sha at the time of
`bug-a-stack-overflow-fault-to-raise-loops-forever-without-an-sp-reset`.)

This is exactly what `test_signal_altstack.pas` says: a stack-overflow SIGSEGV is
the one fault a handler cannot take on the faulting stack, because the fault
happens BECAUSE there is no stack left, so pushing a signal frame onto it faults
again and the kernel kills the process. x86-64 was fixed at
feature-signal-siginfo-ucontext item 3; the other four were never done.

## Why it surfaced now

`__pxxSigSPPtr` (this session) makes a stack overflow *catchable* — the handler
rewrites the saved SP as well as the saved PC, so the raise stub resumes on a
stack with room instead of re-faulting on the guard page forever. That works on
all five targets, and `test_signal_sp_rewrite` proves the per-arch SP offset on
all five. But the end-to-end test, `test_stack_overflow_raise`, is **x86-64 only**
— not because the SP rewrite is missing elsewhere, but because on the other four
the handler never runs at all, so there is nobody to do the rewrite.

## Shape of the fix

Mirror what x86-64 already does, per backend:

1. `BSS_SIG_ALTSTK` is allocated unconditionally already (`ir_codegen.inc:509`),
   so no new BSS.
2. Emit the `sigaltstack(2)` call (syscall numbers differ per arch) with
   `ss_sp = @BSS_SIG_ALTSTK`, `ss_flags = 0`, `ss_size = SIG_ALTSTACK_SIZE`.
3. Or the `SA_ONSTACK` bit ($08000000) into the flags word each target's
   `rt_sigaction` passes.

Four near-identical stubs; the x86-64 one at `ir_codegen.inc:620-650` is the
model, including the comment recording that without it the measured result is
"exit 139 with the hook never entered".

## Gate

Per target: `test_signal_altstack` (which currently has no cross rows) and
`test_stack_overflow_raise` promoted from x86-64-only to all five, plus
self-host byte-identical. Cross-target breadth is Track T's, against that sha.

---

## Resolution (2026-08-21) — three of four fixed, the fourth measured and filed

Each of the four targets got what x86-64 already had: a `sigaltstack(2)` call at
the install site, filling the `stack_t` from `BSS_SIG_ALTSTK`, plus `SA_ONSTACK`
in the flags. **Neither half works alone**, which is why they land together.

### The BSS allocation moved first, and that was the real bug underneath

`BSS_SIG_ALTSTK` / `_ALTSS` were allocated inside **x86-64's**
`EmitSignalRuntime`. On every other target they therefore read **0** — aliased
onto `BSS[0]`, so the first non-x86-64 target to write through them would have
corrupted whatever lives there. They now live in `EnsureSignalBss`, which exists
for exactly this reason and whose comment already told the story about
`BSS_SIG_HOOKS` / `_CODE` / `_ADDR` / `_CTX`. Same lesson, one slot later.

### Per-target, and they are not copies of each other

| target | sigaltstack | `stack_t` | the wrinkle |
| --- | --- | --- | --- |
| aarch64 | 132 (generic table) | 24 B: `ss_sp(8)`, `ss_flags(4+4 pad)`, `ss_size(8)` | `SA_ONSTACK` is a logical immediate: `orr w11, w11, #$08000000` encodes as N=0, imms=0, immr=5 |
| arm32 | **186** (EABI) | 12 B | r7 already framed by the install prologue; r3 carries the signal number across |
| i386 | **186** (int 0x80) | 12 B | **ebx is both the first syscall argument and where the signal number is parked**, so it goes on the stack across this call — the only port that needs it |
| riscv32 | 132 (generic — riscv shares arm64's table, not i386/arm32's) | 12 B | only `a0` changes across an `ecall`, so `t2`/`t3` survive it |

### Measured

A handler that does nothing but `Halt(9)`, against an unbounded recursion —
before, all four were killed with the hook never entered:

| target | before | after |
| --- | --- | --- |
| i386 | 139 | **9** |
| arm32 | 139 | **9** |
| aarch64 | 139 | **9** |
| riscv32 | 139 | 139 — see below |

`test_signal_altstack` now also passes on i386, arm32 and aarch64, with its
third line (`handler-off-faulting-stack=TRUE`) confirming the handler's frame is
hundreds of MB from the fault rather than a few KB.

### riscv32 does not take, and the failure is measured, not guessed

Its registration is **correct**: `qemu-riscv32 -strace` shows
`sigaltstack(0x8089550,(nil)) = 0` before each `rt_sigaction` (a zero return
means ss_sp/ss_size arrived intact), and the flags word was read back out of the
emitted image — `lui t0, 0x18` + `addi t0, t0, 4` = **$18000004** — rather than
assumed. Yet a nil-deref probe shows the handler's frame at `0x2AAAB...`, the
guest **stack**, where i386/arm32/aarch64 all put it in the BSS alt stack. Same
qemu build, same construction.

That points at qemu-user's riscv signal frame, and this box has no RISC-V
hardware and no second emulator to separate "riscv-specific there" from
"riscv-specific here". Filed with the full measurement as
[[bug-a-riscv32-sa-onstack-has-no-effect-under-qemu]] (prio 25). The code stays:
it is correct code asking for correct behaviour, not a workaround, and it starts
working the moment the other side does.

### Tests

`test_stack_overflow_raise` promoted from x86-64-only to **four** targets
(Makefile rows next to each `test_halt_exit_code` row). riscv32 is excluded with
the ticket named, not silently skipped. `test_signal_altstack` stays native-only
deliberately: it asserts `si_code`, which is SEGV_MAPERR(1) on x86-64/i386 and
SEGV_ACCERR(2) on arm32/aarch64 — a real per-arch difference that would make the
cross rows environment-sensitive for no extra coverage, since
`test_stack_overflow_raise` already proves the handler ran.

### Gate

`make compiler/pascal26` (byte-identical fixedpoint) + the four-target probe +
`tools/gate.sh quick`. Cross-target breadth is Track T's, against this sha.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
