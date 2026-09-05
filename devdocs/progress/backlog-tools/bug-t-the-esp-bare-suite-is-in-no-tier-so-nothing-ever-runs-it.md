---
slug: bug-t-the-esp-bare-suite-is-in-no-tier-so-nothing-ever-runs-it
track: T+S
prio: 45
type: bug
blocked-by: []
status: backlog
found: 2026-08-30
found-by: frankS
summary: "test-esp-bare and test-esp-softfloat appear in ZERO testmgr tiers and in no script -- only test-xtensa is enrolled. Re-verified 2026-09-05, and the suite was then EXECUTED for the first time: it immediately caught bug-a-no-program-declaring-a-class-can-build-for-esp-profile-bare, a profile-wide compiler defect present indefinitely. The assertion count in the original body is WRONG (see the 2026-09-05 note): 27 sites in test-esp-bare and 2 in test-esp-softfloat, and on a box WITH the Espressif qemu builds NONE of them skip -- so the '92% skip, maybe split the 2 hosted rows out' advice is a property of the measuring box, not of the target. Post-fix clean run: rc=0, 26 distinct assertions all ok, 0 skipped. Enrolment is still Track T's, in tools/testmgr.py, untouched here."
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

## 2026-09-05 (frankS) — the suite was RUN, and the assertion count above is wrong

**The enrolment claim still holds**, re-verified: `test-esp-bare` and
`test-esp-softfloat` appear in zero testmgr tiers and no script; only
`test-xtensa` is enrolled (`tools/testmgr.py:249`).

**The assertion count does not hold, and the design advice built on it does
not either.** This ticket says *"26 assertions, 24 of those behind `not
installed` guards, only 2 unconditional"*, and recommends possibly splitting
the 2 hosted rows out rather than enrolling a target that is *"92% skip"*.

That count was taken on a box **without** `~/.espressif`. Corrected, by
bounding each recipe at the next target rather than by a line range:

| | assertion sites |
| --- | --- |
| `test-esp-bare` (25955–26168) | **27** — 25 guarded `diff … exit 1`, plus 2 `expect_same` |
| `test-esp-softfloat` (26169–26186) | **2** |
| total | **29** |

**On a box WITH the Espressif qemu builds, none of them skip.** So the "92%
skip" figure is a property of the measuring box, not of the target, and
splitting out "the 2 unconditional rows" would solve a problem such a box does
not have. The honest form of the recommendation is: **enrolment value depends
on whether the runner has `~/.espressif`, and that is a fact about the runner,
not about the suite.**

*(An intermediate count of "24 in test-esp-softfloat", relayed by this author
earlier the same evening, was wrong: the line range used ran past the target's
end into `qemu-env-check`. The number above is bounded at the next target and
is the one to use.)*

## It was executed for the first time, and it caught a real defect immediately

`PXX_ALLOW_FULL_SUITE=1 make -k test-esp-bare test-esp-softfloat` on plexus
(both Espressif qemu builds present, `esp_develop_9.2.2_20250817`).

**First run, compiler `fe1e9c37d322`:** 1 MISMATCH — `esp32c3 exception`,
oracle 12 lines, device output empty. That was **not** a device fault and not
chip-specific; it was
`bug-a-no-program-declaring-a-class-can-build-for-esp-profile-bare` —
**no program declaring a `class` could build for `--esp-profile=bare` at all,
on either chip.** A five-line program reproduces it.

**After that fix, clean run:** `rc=0`, **26 distinct assertion outcomes all ok**
(28 lines; the 2 softfloat rows execute under both targets), **0 MISMATCH,
0 skipped, 0 build failures.**

So the answer to *"what would enrolment actually buy"* is now measured rather
than estimated: on a box with the toolchains it buys 26 real cross-checked
assertions against the x86-64 oracle, and the first time anyone ran them they
found a profile-wide compiler defect that had been present indefinitely.

**Method note, since this ticket is about invisibility.** Two runs during this
work were **discarded** because `tools/esp_run_bare.sh` was edited while they
were executing — `/bin/sh` reads a script incrementally. Established by
timestamps (script 20:22:43; both logs still being written at 20:22:47 and
20:22:48), not by feel. The tell was a row count no clean run produces (`ok=3`
where the clean run had 16). The defect above does not rest on either discarded
run: it was confirmed by a by-hand compile, a five-line repro on both chips, and
the same program building under `--platform=posix`.

**Still Track T's to enrol** — `tools/testmgr.py` is T's file and this seat has
not touched it. What changed is that the enrolment question now has a measured
answer behind it instead of an estimate.
