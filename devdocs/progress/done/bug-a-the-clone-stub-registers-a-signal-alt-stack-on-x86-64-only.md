---
slug: bug-a-the-clone-stub-registers-a-signal-alt-stack-on-x86-64-only
track: A
prio: 40
type: bug
blocked-by: []
status: done
found: 2026-09-02
found-by: frankA
owner: rd
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

## Resolution (2026-11-20, rd)

Done the way the section above says to, with the test first: the
registration is read back with `sigaltstack(NULL, &old)` inside each worker,
which does not depend on SA_ONSTACK delivery under qemu.

test/test_a_a_cloned_thread_registers_its_own_alt_stack.pas, test-threads
rows on x86-64, aarch64, arm32 and i386, before the change:

    x86_64:  registered=2/2 size-ok=2/2 above-own-frame=2/2 distinct=TRUE
    aarch64: registered=0/2 size-ok=0/2 above-own-frame=0/2 distinct=FALSE
    arm32:   (same as aarch64)
    i386:    (same as aarch64)

After, all four print the x86-64 line, four runs each.

`EnsureCloneStub` (compiler/thread_emit.inc), in each of the three legs:
- carves SIG_ALTSTACK_SIZE between the hidden-destination scratch and the TLS
  block (the x86-64 placement: the top of the mapping, away from the guard
  page);
- registers it in the child, after the TLS install and before the entry,
  with a stack_t built on the child's own stack (i386 `int 0x80` 186, arm32
  `svc 0` 186, aarch64 `svc #0` 132);
- moves the scratch pointer up by SIG_ALTSTACK_SIZE.

aarch64 carves on every kernel, so the offsets have one answer, and registers
on Linux only. Its FreeBSD (thr_new) and NetBSD/OpenBSD (translator) child
paths reach the same code, but sigaltstack through them is not measured
here. The new aarch64, arm32 and i386 encodings were checked word for word
against clang's assembler. PAL_MIN_STACK (128 KB) already covers the carve on
every target: it was unconditional.

The test keeps both workers alive until both have read their registration.
PalThreadCreate reaps a dead thread's stack, so without that barrier worker 1
could reuse worker 0's mapping, and `distinct` read FALSE once on aarch64.
