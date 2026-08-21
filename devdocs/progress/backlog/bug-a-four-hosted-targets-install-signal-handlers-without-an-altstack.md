---
slug: bug-a-four-hosted-targets-install-signal-handlers-without-an-altstack
track: A
prio: 40
status: backlog
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
