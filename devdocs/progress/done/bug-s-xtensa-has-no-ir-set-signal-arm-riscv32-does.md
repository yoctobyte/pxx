---
slug: bug-s-xtensa-has-no-ir-set-signal-arm-riscv32-does
track: A+S
prio: 35
type: bug
blocked-by: []
status: done
summary: "FIXED, verified 2026-09-05. ir_codegen_xtensa.inc:4580 has a real IR_SET_SIGNAL arm ('riscv32's arm is the model; the register pair is xtensa's'). Verified by running, not by grepping: test_cross_signal_runtime_predicate answers `signals yes` on xtensa, and test_signal_altstack compiles and passes under qemu-xtensa with the Makefile's own flags -- `recursing / code=2 / handler-off-faulting-stack=TRUE / exit=0`. The arm landed with other work and the ticket was never closed."
owner: unassigned
---

# xtensa has no IR_SET_SIGNAL arm

> **CORRECTION — I filed this at the wrong size (frankS, 2026-08-30).**
> I priced it as "riscv32 has the arm, port it" without checking what the arm
> calls. It calls `SigSetHookAddr`, and on xtensa nothing ever sets it:
> `EmitSignalRuntimeForTarget` has arms for five arches and falls through for
> xtensa **on purpose** — *"FreeRTOS is not a Unix and has no signal runtime at
> all"* — a rationale written before the hosted profile existed. Porting the arm
> alone would emit a call to offset 0.
>
> Re-filed at its real size and scope as
> [[feature-a-a-signal-runtime-for-HOSTED-xtensa-the-exclusion-predates-the-profile]],
> where it is worth **more** than this ticket claimed, not less: the three
> SA_SIGINFO refusals are gated on the same missing runtime, so one piece of work
> closes four programs.
>
> Work this ticket, and the estimate in it, from that one. Left here rather than
> `rejected/` because the diagnostic observation below is still accurate.


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

## Verified fixed 2026-09-05 (frankS)

Checked by running on the target, not by counting greps — a `grep -c` of
`IR_SET_SIGNAL` returns 1 for every backend including the ones that only mention
it in a comment, so the count could not have told a real arm from a refusal.

- `ir_codegen_xtensa.inc:4580` — a real `IR_SET_SIGNAL` case, comment reads
  *"riscv32's arm is the model; the register pair is xtensa's"*.
- `test_cross_signal_runtime_predicate` on `--target=xtensa --platform=posix`
  prints `signals yes`.
- `test_signal_altstack` under `qemu-xtensa` with the Makefile's own flags
  (`--xtensa-soft-mulhigh -Fulib/rtl`) prints
  `recursing / code=2 / handler-off-faulting-stack=TRUE`, exit 0 — the row
  Makefile:22150 already asserts.

Worth recording how nearly this went the other way: my first run omitted
`--xtensa-soft-mulhigh` and the test died with `uncaught target signal 4
(Illegal instruction)`. A probe misconfiguration wearing the exact shape of a
codegen bug on the one target where a missing multiply-high instruction is
plausible. The Makefile row carries that flag; my hand-run did not.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 87f818e2e.
