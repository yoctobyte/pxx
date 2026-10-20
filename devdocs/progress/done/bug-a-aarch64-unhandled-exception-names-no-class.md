---
track: A
prio: 20
type: bug
---

# An uncaught exception on aarch64 printed only "Unhandled exception"

Reported 2026-10-20 by neo-73, while chasing Vloot's EMFILE on via. Only the
x86-64 emitter (exception_emit.inc) wrote the detail line
`Unhandled exception: <ClassName>: <Message>`. aarch64 wrote the bare line, so
the OSError took instrumentation to name.

**Fix:** the aarch64 block now emits the x86-64 sequence instruction for
instruction, with the same layouts and the same range guards. An object that
isn't an Exception, a nameless class, and an empty or >4 KB message each fall
back to the shorter line, as on x86-64. Checked under qemu-aarch64 with OSError,
ValueError, a message-less user class and a 5000-character message; the output
is identical to x86-64.

Test: `test_nilpy_unhandled_names_the_exception` (x86-64, and aarch64 under
qemu). Still bare: i386, arm32, riscv32, xtensa
(backlog: feature-a-unhandled-exception-detail-on-the-other-targets).
