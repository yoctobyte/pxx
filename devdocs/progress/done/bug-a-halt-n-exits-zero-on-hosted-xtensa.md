---
track: A+S
type: bug
prio: 55
status: done
found: 2026-08-30
found-by: frankS
---

# `Halt(n)` exits ZERO on hosted xtensa — and the differential row that covers it was green

```pascal
program h1;
begin writeln('bye'); Halt(5); end.
```

| target | stdout | exit code |
| --- | --- | --- |
| x86-64 | `bye` | **5** |
| riscv32 | `bye` | **5** |
| **xtensa (hosted, Call0)** | `bye` | **0** |

A program's failure signal vanished with no diagnostic.

## Cause — a COPY of the pre-fix riscv32 arm, comment included

`IR_TERMINATE` in `ir_codegen_xtensa.inc` emitted `EmitExit(0)` unconditionally
under the comment *"bare-metal: park in a self-loop"*. The argument was
evaluated nowhere and discarded. `EmitExitReg` (`emit.inc`) had the same shape:
its xtensa arm parked unconditionally, in a routine whose sibling `EmitExit`
had already learnt the hosted/ESP difference twenty lines above.

That is character for character
[[bug-a-halt-n-exits-zero-on-hosted-riscv32]] — including the misleading
comment, which is the tell: this is a *copy* of the pre-fix riscv32 arm, not an
independent oversight. `EmitExitReg` was extracted specifically to stop the
six hand-written copies of this rule from drifting, and xtensa's arm was
written into the extraction still carrying the bug.

## The part worth more than the fix: A GREEN ROW THAT DOES NOT ASSERT ITS OWN SUBJECT

`test_halt_exit_code` is **in the `test-xtensa` target and it PASSED.** The row
compared stdout, and stdout was right — `working / halting with 5` — while the
exit code was 0. riscv32's row for the same program appends `echo "exit=$?"`
and so asserts the thing the program exists to assert; xtensa's row was written
without it.

This is a third mechanism of invisibility on this target, distinct from the two
already recorded:

| mechanism | example |
| --- | --- |
| nothing could execute the target at all | [[why-xtensa-was-the-holdout]] |
| the op is missing, so the program never compiles, so its bug never runs | `test_dynarray_whole_assign`'s store arm |
| **the test runs, and asserts the wrong observable** | **this one** |

The third is the worst of the three, because the first two leave a red or a
gap and this one leaves a **green**. Worth a sweep of its own: any differential
row whose program's subject is an exit code, a signal, or a side effect, and
whose assertion is on stdout.

## Fix

Both arms gate on `TargetPlatform = PLATFORM_ESP` (bare metal genuinely has no
kernel and no status to report one with) and otherwise evaluate the code and
issue `exit_group`. `EmitExitReg`'s xtensa arm moves a2 to a6 **before** loading
the syscall number, because xtensa's map is `nr -> a2, arg0 -> a6` and loading
the number first would overwrite the code with 119.

The `test-xtensa` row now appends `echo "exit=$?"` on both sides.

## Measured after the fix

| | stdout | exit |
| --- | --- | --- |
| `Halt(5)`, Call0 | `bye` | 5 |
| `Halt(5)`, **windowed** | `bye` | 5 |
| `Halt(n)` with a runtime `n = 7` | `code 7` | 7 |
| ESP bare profile | still compiles, still parks | — |

## Bound

Hosted xtensa, `--platform=posix --xtensa-soft-mulhigh`, qemu-xtensa user mode,
both ABIs. ESP bare checked by compiling only — not run on real or emulated ESP
silicon. The claim that this is a copy of the riscv32 arm is from the identical
comment text, not from history.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
