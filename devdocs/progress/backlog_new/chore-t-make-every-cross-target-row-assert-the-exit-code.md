---
track: T
prio: 45
type: chore
status: backlog_new
blocked-by: []
found: 2026-08-30
found-by: pxx-a5, sweeping chore-t-sweep-for-rows-that-assert-stdout-when-the-subject-is-an-exit-code
summary: "536 cross-target differential rows compare stdout only; 5 capture the exit code. Both operands are runs of the same program, so the exit code is free to add — but run_target.sh returns the EMULATOR's status and signal deaths do not encode identically under qemu-user and a native shell, so a blanket rollout can manufacture diffs on exactly the rows most worth checking. Wants a piloted rollout, one arch at a time, verified against Track T's matrix."
---

# Make every cross-target row assert the exit code, one arch at a time

## The measurement (2026-08-30, `Makefile` at `pxx-a5`'s HEAD)

| | |
| --- | --- |
| `expect_same.sh` rows, total | 3053 |
| ...that run a target through `run_target.sh` | 619 |
| ...**cross-target differential** (both operands are runs) | **536** |
| ...of those, capturing `$?` | **5** |
| **compare stdout alone** | **531** |

Both operands of a differential row are runs of the *same program* — one through
`run_target.sh <arch>`, one native x86-64 — so appending `; echo "exit=$$?"` to
each is a free strengthening: the comparison stays valid and now covers a second
observable.

## Why it matters, in one sentence that already happened

`Halt(5)` exited 0 on hosted xtensa, `test_halt_exit_code` was in the target, and
it **PASSED**, because the row compared stdout. A passing row is a completed
obligation; nobody revisits it. That row is fixed and its whole family is now
ratcheted (`tools/exit_observable_devtest.py`). **These 531 are the same shape,
unratcheted.**

*A row that cannot omit the observable is a guard; a row that was remembered to
include it is a habit* — and the xtensa row is what a habit looks like when it
lapses.

## Why it is not a one-line sed, and this is the whole ticket

**`run_target.sh` returns the EMULATOR's exit status.** A program that dies by
signal does not encode identically through qemu-user and through a native shell
(`128+n` conventions, and qemu's own failure statuses sit in the same range). A
blanket append can therefore manufacture diffs on exactly the rows most worth
checking — a crash whose *stdout* already matched.

And 531 edits land in a file no lane can gate locally: `make test` is denied by
`.claude/hooks/no-full-suite.sh`, correctly, so the verification has to come from
Track T's matrix against a pushed sha.

## Proposed rollout

1. **One arch first, and the smallest** — i386 or aarch64, whichever has the
   fewest rows. Append to both operands, push, and read T's next full tier for
   that arch alone.
2. **Classify every new red before continuing.** Two outcomes are expected and
   must be told apart: a *real* exit-code divergence (the point of the exercise —
   file it in the owning lane) and an *encoding* difference between qemu and the
   native shell (a harness artefact — fix `run_target.sh` to normalise, do not
   paper over it at the row).
3. Only then the next arch. Stop and re-think if step 2 produces more artefacts
   than findings on the pilot arch — that would mean the normalisation belongs in
   `run_target.sh` before any further rows change.
4. Extend `tools/exit_observable_devtest.py` section 3 downward as each arch
   lands, so the 531 becomes a ratchet that can only fall.

## What is already done

- The confirmed family (halt / signal / runtime-error rows) is complete and
  ratcheted: 10 of 10 capture `$?`, across all six execution paths.
- The cross-arch disagreement rule was run over all 603 programs with per-arch
  rows: **zero splits**. frankS's was the only one.
- The 32 rows naming a program that calls `Halt(n)` were checked individually and
  are **not** findings — `Halt` there is an assertion mechanism, not a subject.

Parent: `chore-t-sweep-for-rows-that-assert-stdout-when-the-subject-is-an-exit-code`.
