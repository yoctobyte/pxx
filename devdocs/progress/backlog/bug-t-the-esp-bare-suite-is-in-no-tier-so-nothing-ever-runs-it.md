---
slug: bug-t-the-esp-bare-suite-is-in-no-tier-so-nothing-ever-runs-it
track: T+S
prio: 45
type: bug
blocked-by: []
status: backlog
found: 2026-08-30
found-by: frankS
summary: "test-esp-bare and test-esp-softfloat appear in ZERO testmgr tiers and in no script — grep across tools/ finds one xtensa/esp job total, test-xtensa. So the ESP bare-metal suite is written, correct, and never executed by any gate or sweep. Found because the one executed windowed row landed there, in a target nothing runs."
---

# The ESP bare-metal suite is enrolled nowhere

Measured, `grep -rn 'test-esp-bare' --include='*.py' --include='*.sh'`:

| | |
| --- | --- |
| xtensa/esp jobs in `tools/testmgr.py` | **1** — `test-xtensa`, in `full` |
| tiers containing `test-esp-bare` | **0** |
| tiers containing `test-esp-softfloat` | **0** |
| references in `tools/gate.sh` or any script | **0** |

Both targets are declared `.PHONY` in the Makefile and are reachable only by
typing them.

## How it was found, which is the part worth keeping

Not by auditing the tier list. `bug-a-the-xtensa-windowed-abi-is-compiled-twice-and-executed-never`
said the windowed ABI was never executed; by the time that ticket was worked,
frank-optimize-b4 had already added the executed windowed canary — **into
`test-esp-bare`**. So the row existed, was correct, used the right two outcome
slots, and still could not fail anything, because nothing runs the target it
sits in.

**That is the same defect one level up.** The ticket's own sentence was *"a suite
whose PASS and whose SKIP print the same thing"*; this is a row whose pass and
whose non-execution print the same thing, which is nothing. Fixing coverage by
adding a correct row to an unenrolled target moves the invisibility rather than
removing it — and it is invisible in exactly the way the first one was, because
a Makefile target looks gated when you are reading the Makefile.

The windowed canaries now live in `test-xtensa` (enrolled, `full`) for this
reason. b4's row in `test-esp-bare` is a harmless duplicate of one of them and
is b4's to keep or drop.

## What enrolment would actually buy, measured rather than assumed

`test-esp-bare`'s recipe is 200 lines with **26 assertions**, and **24 of those
sit behind `not installed` guards** that skip when the Espressif qemu builds are
absent. Only **2** use `tools/run_target.sh` unconditionally.

So on a box without `~/.espressif`, enrolling this target gates 2 real rows and
prints 24 skips — worth doing, but do NOT enrol it and read the resulting green
as "ESP is covered". That is the same misreading `test-xtensa`'s own header
already warns about (*"55/142, not GREEN"*), and the honest form is the same:
name the skipped population in the job's comment.

The prior question is whether the watcher box has the Espressif toolchains at
all. If it does not, the useful move may be to split the 2 unconditional hosted
rows out into an enrolled target and leave the 24 hardware-dependent ones where
they are, rather than enrolling a target that is 92% skip.

## Track letter

**T+S.** The enrolment lives in `tools/testmgr.py`, which is Track T's file, so
this is filed rather than fixed — T owns the tool. The *reason to care* is Track
S's: ESP is S's campaign and this is S's suite going unrun. The Makefile side of
any split would be S's to write.
