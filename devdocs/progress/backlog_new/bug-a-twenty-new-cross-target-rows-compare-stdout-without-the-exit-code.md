---
track: A
prio: 40
type: bug
blocked-by: []
summary: "The stdout-only ratchet in tools/exit_observable_devtest.py was armed at 531 this morning (f444a4a33) and reads 551 tonight. 20 new cross-target differential rows compare stdout and not the exit status, attributed exactly to four commits in three lanes. The exposure is the shape frankS's Halt(5)-exits-0 bug lived in; the fix is mechanical. tools-devtest is red in the limited and full tiers until it lands."
status: new
owner: ""
---

> **NOT a duplicate of `chore-t-make-every-cross-target-row-assert-the-exit-code` [T p45]** — checked by the
> coordinator 2026-08-30 after `progress.sh check` raised NEAR-DUP on four shared slug words. They are a
> **regression** and a **campaign**, and merging them would lose one of the two. THIS ticket is bounded: the
> ratchet was armed at 531 and reads 551, so **20 specific rows** regressed across four commits in three
> lanes, and `tools-devtest` is RED in the limited and full tiers until they land. That ticket is the
> general rollout of all 531, which needs piloting one arch at a time. Fix this one first — it is smaller,
> it clears a red tier, and it does not depend on the campaign's outcome.

# 20 new cross-target rows compare stdout without the exit code

- **Type:** bug (Track A — the rows are `Makefile` recipe lines).
- **Found:** 2026-08-30 by Track T (face 2), from the ratchet going red;
  independently seen by the coordinator. Filed by T, not fixed by T.

## The measurement, and it attributes exactly

`tools/exit_observable_devtest.py` section 3 counts rows that run
`tools/run_target.sh` with two `"$$(` captures — a cross-target differential —
and subtracts the ones that also capture `exit=$$?`. It was armed at **531**
this morning by `f444a4a33` (*"the exposure is 531 stdout-only rows"*).

Counted at each commit that touched the Makefile since:

| sha | lane | stdout-only | delta |
| --- | --- | --- | --- |
| `f444a4a33` | T (armed here) | 531 | — |
| `8b85e4881` | **P** — the bound-name harvest | 544 | **+13** |
| `df690b519` | **A+S** — SPECIAL_IN in both 32-bit cross backends | 548 | **+4** |
| `df8731b1f` | **O** — -O3 aarch64 fuses the resident read | 550 | **+2** |
| `6ef921b4e` | **O** — -O3 aarch64 collapses the last push/pop | 551 | **+1** |

Four commits, three lanes, six hours. **The ratchet is working** — this is the
success case, not a stale number: it caught a 20-row drift within hours of being
armed, and the drift is attributable because it was armed at all.

## Why the rows matter

A cross-target differential row runs the same program natively and on a cross
target and compares **stdout**. It does not compare the exit status. So a
program that `Halt(5)`s on one target and exits 0 on the other, with identical
output, **passes**. That is not hypothetical — it is the exact shape frankS's
xtensa bug lived in, and it is why the family guard in section 1 exists at all.

The fix is mechanical and free: both sides are runs of the same program, so
appending `; echo "exit=$$?"` inside each capture costs nothing and closes it.
20 rows, in the four commits above.

## What this ticket does NOT ask for

Not the other 531. That number is a standing exposure with its own history, and
closing it is a separate, much larger call. This ticket is the **20 that landed
after the line was drawn**, because those are the ones whose authors are known,
whose diffs are small, and who can fix them for the cost of a `sed`.

## The gate cost, stated rather than absorbed

`tools-devtest` is enrolled in the **limited** and **full** tiers (not quick,
not native). So this red does not touch any lane's per-fix loop, and it does not
block a push — but it is red in every watcher sweep until it lands, and it will
keep auto-filing.

**Do not resolve this by bumping the ratchet.** A high-water mark that is raised
whenever it is reached measures nothing; it is the same move as widening a
tolerance until the guard stops complaining, which
`chore-a-re-include-bench-timing-in-tools-devtest` is the cautionary tale for.
If the standing red is judged too expensive to hold while the rows are fixed,
the honest alternative is to make section 3 **report the drift and its
attribution without failing** — its own docstring says its job is that the
number "cannot drift upward unnoticed", and noticing does not require a gate
failure. That is a Track U call about what a shared gate should do when the
number it watches grows as a side effect of other lanes' normal work; it is not
something to settle by editing the constant.
