---
slug: chore-t-sweep-for-rows-that-assert-stdout-when-the-subject-is-an-exit-code
track: T
prio: 55
status: done
owner: pxx-a5
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

---

## SWEPT 2026-08-30 — the family is clean; the exposure is not a list

### The answer to "how many rows share the shape": in the confirmed family, zero

Every row whose **subject** is an exit status or a signal now captures `$?` —
**10 of 10**, across all six execution paths:

| row | Makefile |
| --- | --- |
| native `test_halt_exit26` | 6012 |
| i386 / aarch64 / riscv32 / **xtensa** / arm32 halt | 11763 / 12170 / 12340 / 12845 / 13358 |
| `test_signal_handlers26`, `test_signal_altstack26` | 5883, 5899 |
| `test_div_zero_re20026` ×2 (runtime error 200) | 6913, 6914 |

The coordinator's mechanical rule — *"where riscv32 and xtensa rows exist for one
program and only one captures the exit code, the other is a finding"* — was run
over **all 603 programs that have per-arch rows**. It returns **zero splits**.
frankS's was the only one, and it is fixed.

### The 32 near-misses, and why listing them would be the same mistake

A `Halt(n)`-with-a-nonzero-literal scan over `test/**` finds 117 programs and 32
uncaptured rows. **None is a finding**, and I checked rather than assumed:
`lib_dns_resolve` does `Halt(1)` on failure and `Halt(0)` on success — an
assertion mechanism, not a subject. `crtl_atexit`'s subject is LIFO handler
*order*; `exit()` is one of the two paths that must produce it, and the ordering
is on stdout where the row already looks.

Reporting those 32 would be 32 findings that cost nobody anything, which is how a
check earns the habit of being scrolled past — the `STALE-EDGE-HIDDEN`
calibration argument, and the reason the guard's family is an explicit list with
a reason per entry rather than a `Halt(` heuristic. A heuristic cannot tell *the
code under test* from *how this test fails*, and it gets 32 wrong.

### The real exposure, which is structural and has a number

**536 cross-target differential rows. 5 capture the exit code. 531 compare stdout
alone.**

Both operands of those rows are *runs of the same program* — one through
`run_target.sh <arch>`, one native — so the exit code is free to add and is
currently unchecked on every one of them. **This is the shape frankS's bug lived
in**, and it is not an audit list: it is a property of how the rows are written.

### What I built, and what I did not

**Built:** `tools/exit_observable_devtest.py` — 9 guards, 0 FAIL. Section 1 is the
ratchet: any row naming a family member must capture `$?`. Section 2 proves it
discriminates, against the xtensa row *as it was actually written*. Section 3
holds the 531 at its measured size, so the exposure cannot grow while the family
stays green — a guard on what the guard cannot check.

**Not built: the 531-row mechanical edit**, and this is a recommendation, not a
deferral. Appending `; echo "exit=$$?"` to both operands of every cross-target
row is the right structural fix — *a row that cannot omit the observable is a
guard; a row that was remembered to include it is a habit* — but it carries a
risk the sweep surfaced and cannot settle from reading:

- `run_target.sh` returns the **emulator's** exit status. For a program that dies
  by signal, qemu-user and a native shell do not encode that identically, so a
  blanket rollout can manufacture diffs on exactly the rows most worth checking.
- 531 edits land in a file no lane can gate locally (`make test` is denied here
  by policy, and rightly).

So it wants a **piloted rollout, one arch at a time, verified against Track T's
matrix** — filed as
`chore-t-make-every-cross-target-row-assert-the-exit-code` with the numbers,
the risk, and the pilot order. Landing 531 blind edits at the end of a session,
ungated, would be the same class of act as the row that started this ticket:
something that looks like coverage.

### Note on the guard's own first cut

Its coverage check reported **5 of 10** family members reachable, which read as a
gap. It was the regex: native binaries carry a `26` suffix, `26` is a word
character, and `\b` after the program name matched nothing. Then it read **9 of
10**, because attributing each row to its *longest* match hides that a row naming
`test_halt_exit_code` also names `test_halt_exit`. Both were the instrument, not
the tree — twice in one file, in a session about exactly that.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
