---
slug: chore-t-sweep-for-rows-that-assert-stdout-when-the-subject-is-an-exit-code
track: T
prio: 55
status: open
---

# Sweep for differential rows that assert stdout when the subject is an exit code

**Found by frankS, 2026-08-30, by accident — and it says so, which is why this
ticket exists rather than a one-line fix.**

`Halt(5)` **exited 0** on hosted xtensa. `IR_TERMINATE` emitted `EmitExit(0)`
unconditionally, under a comment claiming *"bare-metal: park in a self-loop"* —
character for character the riscv32 bug, **misleading comment included**, which is
the tell that it was copied from the pre-fix riscv32 arm rather than written
independently.

**The bug is filed and fixed** (`bug-a-halt-n-exits-zero-on-hosted-xtensa`). This
ticket is about how it stayed invisible.

## The third mode of invisibility, and it is the worst

`test_halt_exit_code` **is** in the `test-xtensa` target, and it **PASSED**. The
row compares **stdout** — which was correct, `halting with 5` — while the exit code
was 0. riscv32's row for the same program appends `echo "exit=$?"`. Xtensa's was
written without it.

| situation | what you get |
| --- | --- |
| nothing can execute the target | a **gap** |
| the op is missing, the program never runs | a **gap** |
| **the row runs and asserts the wrong observable** | a **GREEN** |

The first two leave something visible; a gap gets counted, and someone eventually
asks about it. The third produces a **passing row**, and a passing row is a
completed obligation — nobody revisits it, and its existence is positive evidence
that the property is covered.

This is face 118 in its harshest form. *Co-location makes drift visible; only an
oracle makes it fail* — **but an oracle pointed at the wrong observable makes it
pass.** Compare 121 (a self-differential's reference cannot be wrong) and 126 (an
instrument that cannot see a defect reads like one reporting its absence): three
routes to the same place, and this is the only one that manufactures a green.

## The sweep

**Any differential row whose program's subject is an exit code, a signal, or a side
effect, and whose assertion is on stdout only.** Exit-code rows are the seed set
because we have a confirmed instance; signals and side effects are the same shape.

Mechanical starting point: rows whose program name or body contains `Halt`,
`ExitCode`, `RunError`, `raise`/`abort`, or a file/socket side effect, cross-checked
against whether the row captures `$?` at all. Where riscv32 and xtensa rows exist
for one program and only one captures the exit code, the other is a finding.

## Why it is a T ticket and not a fix

The one instance is fixed. What is unknown is **how many rows share the shape** —
and that is a property of the harness, which is Track T's. frankS's own framing is
the reason it must be swept rather than watched for:

> *"I only found this one because my sweep harness compares returncode AND output
> and the Makefile row does not — i.e. I found it by accident, which is not a
> method."*

**Fix direction, once the set is known:** prefer making the harness capture the exit
code for every row over auditing rows one at a time. A row that *cannot* omit the
observable is a guard; a row that was remembered to include it is a habit, and the
xtensa row is what a habit looks like when it lapses.
