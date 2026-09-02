---
slug: bug-a-the-clone-stub-registers-a-signal-alt-stack-on-x86-64-only
track: A
prio: 40
type: bug
blocked-by: []
status: backlog
found: 2026-09-02
found-by: frankA
owner: unassigned
summary: "EnsureCloneStub has four legs -- x86-64, i386, aarch64, arm32 -- and only the x86-64 one carves and registers a per-thread signal alt stack. All five backends DO register one for the installing thread (grepping for syscall 131 finds only x86-64 because the number is per-arch: 186 on i386/arm32, 132 on aarch64/riscv32), so on every non-x86-64 target a cloned thread still has sp=0 flags=SS_DISABLE and its stack overflow is unhandleable. NOT DONE WITH THE x86-64 FIX BECAUSE IT COULD NOT BE VERIFIED: SA_ONSTACK is already known not to take effect under qemu (bug-a-riscv32-sa-onstack-has-no-effect-under-qemu), which is the only way to run these targets here, so the code would have been written and not tested."
---

# The clone stub's alt stack is x86-64 only

`bug-a-a-cloned-thread-has-no-sigaltstack-so-its-stack-overflow-is-unhandleable`
is fixed for x86-64: the clone stub carves `SIG_ALTSTACK_SIZE` off the top of
the child's stack, above the TLS block it already carves, and registers it with
`sigaltstack(2)` before the entry point runs. Measured, one binary one argument
apart: a worker's stack overflow went from `139` with no output to handled,
`exit 7`, with the handler provably on the worker's own stack and not the
process-wide BSS buffer.

`EnsureCloneStub` (`compiler/thread_emit.inc`) has three more legs and none of
them do this:

| leg | line | alt stack in the child |
| --- | --- | --- |
| x86-64 | 45 | yes |
| i386 | 167 | no |
| aarch64 | 215 | no |
| arm32 | 246 | no |

## The grep that would say otherwise, and why it is wrong

`grep -n 131 compiler/ir_codegen*.inc` finds `sigaltstack` only in the x86-64
backend and reads as "only x86-64 has an alt stack at all". **It is the wrong
spelling.** The syscall number is per-architecture — 186 on i386 and arm32, 132
on aarch64 and riscv32 — and every one of the five backends registers a buffer
for the installing thread (`BSS_SIG_ALTSTK`, two references in each). So the
main thread is covered everywhere and only the CLONED thread is not, which is
the same shape the x86-64 leg had.

## Why it was not done in the same change

The property under test is "the kernel delivered a signal onto the alt stack".
The only way to run i386, aarch64 and arm32 on this box is qemu-user, and
[[bug-a-riscv32-sa-onstack-has-no-effect-under-qemu]] already records that
`SA_ONSTACK` does not take effect there. So a cross run cannot distinguish "my
stub is wrong" from "qemu ignores the flag", and the code would have been
written and asserted by a test that cannot fail. Writing three untestable legs
is worse than three that are absent and named.

Whoever takes this needs either hardware or a way to observe the registration
directly rather than its effect — `sigaltstack(NULL, &old)` from inside the
child reports `ss_sp` and `ss_size`, which qemu does have to emulate correctly
for the program to see anything at all, and which does not depend on signal
delivery working. That is the shape of the test to write FIRST.

## The floor this imposes

`lib/rtl/palthread.pas` gained `PAL_MIN_STACK = 128 * 1024`, because the stub
now carves 1152 + 32768 bytes off the top before the child's first instruction
and a smaller request would have the stub writing past the mapping. The three
non-x86-64 legs will need the same arithmetic, and the constant is already a
second copy of the compiler's two — that is stated at its declaration.
