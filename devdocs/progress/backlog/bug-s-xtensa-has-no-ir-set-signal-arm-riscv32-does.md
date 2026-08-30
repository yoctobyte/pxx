---
slug: bug-s-xtensa-has-no-ir-set-signal-arm-riscv32-does
track: A+S
prio: 35
type: bug
blocked-by: []
status: backlog
summary: "`ir_codegen_xtensa.inc` has no IR_SET_SIGNAL case, so any program installing a signal handler dies with `unsupported node in IR codegen: unknown`. riscv32 has the arm; xtensa is the only hosted backend without it. The op is also one of the seven IROpName does not name, which is why the message says `unknown` instead of naming it."
owner: unassigned
---

# xtensa has no IR_SET_SIGNAL arm

`test_signal_handler_callback_b336` fails:

```
error: target xtensa: unsupported node in IR codegen: unknown
```

`unknown` because `IR_SET_SIGNAL` is one of the seven ops `IROpName` does not
name (see [[bug-a-iropname-has-no-entry-for-seven-ir-ops-so-a-missing-arm-reports-unknown]]);
identifying it needed a cross-backend grep, not the diagnostic.

`ir_codegen_riscv32.inc` has the arm. Port it — riscv32 is the closest model
(32-bit, same `rt_sigaction` shape), with xtensa's own syscall number:
`SYS_rt_sigaction = 226` (measured, see
[[feature-s-the-xtensa-row-of-the-posix-syscall-table]]).

Two other ops are missing from **both** 32-bit backends and are out of scope
here, noted so they are not rediscovered: `IR_IMTADDR`, `IR_IO_LOCK`,
`IR_IO_UNLOCK`.

Found by [[feature-s-the-xtensa-row-of-the-posix-syscall-table]] — the program
could not reach codegen before the syscall table existed.
