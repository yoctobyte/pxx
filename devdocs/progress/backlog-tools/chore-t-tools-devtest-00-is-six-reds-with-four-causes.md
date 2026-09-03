---
track: T
prio: 65
type: chore
status: backlog
found: 2026-09-03
found-by: claude-T
owner: ""
blocked-by: []
summary: "tools-devtest#00 is the ONLY red job left in the full tier and has been red in all 8 full runs of 2026-09-02, while native is GREEN — so it is invisible to every lane gating on native or `gate.sh quick`. Its 6 failing guards are FOUR causes, not one: a sync.sh fold-safety refusal added 2026-08-29 trips two guards written before it; three are censuses/ratchets working correctly and reporting real tree drift (one already has a decide- ticket); one is a genuine behavioural gap (the bench fingerprint ignores the CPU governor). Only ONE of the four is a plain bug to fix."
---

# `tools-devtest#00` is six reds with four causes

## Why it matters now, when it did not this morning

Earlier on 2026-09-02 this job was correctly described as **off the critical
path**: it sits inside the pin's `pin_baseline`, so `pin_shadow` waives it as
`inherited` and it has never blocked a pin. That is still true.

What changed is that **it is now the only red job in the full tier.** Everything
else red during the day was cleared by the fleet. So it is the sole thing between
this tree and a `full` run with no RED tier — which is exactly what
`pin_is_green` requires, and therefore the only thing standing between the fleet
and its **first fresh rollback target since v354 on 2026-08-19**.

`native` is GREEN, so this red is invisible to every lane that gates on native or
on `gate.sh quick`, which is most of them.

## Six reds, four causes

Ran all six directly rather than reading the report.

### Cause 1 — a sync.sh safety refusal trips two guards written before it (2 reds)

`tools/sync_pending_commit_devtest.py` and `tools/devtest_sync_fold.py`.

Both die inside `sync.sh`:

```
sync: still mid-rebase after resolution — refusing to amend
sync: this would fold two of your commits into one; run:
sync:   git status   # then finish or abort the rebase by hand
```

That refusal was added by **`f81498db8`, 2026-08-29** — *"sync.sh could fold two
of your commits into one, silently"* — and adjusted twice since (`e27386855`,
`caecfd610`). `sync_pending_commit_devtest.py` was last touched **2026-08-19**,
ten days before the refusal existed. So the guard's fixture drives sync.sh into a
state the tool now correctly declines to continue from.

**The refusal is almost certainly right and the guards are almost certainly
stale** — but that is a judgement about whether the fixture's mid-rebase state is
one a caller should ever reach, and it belongs to whoever owns the fold guard.
Do NOT "fix" this by loosening the refusal: `f81498db8` exists because the silent
fold lost work.

### Cause 2 — three censuses reporting real drift, all working correctly (3 reds)

These are not broken. They are policy assertions and the tree has moved past
them.

| guard | what it says |
| --- | --- |
| `exit_observable_devtest` | stdout-only share is **676 of 727 = 92.98%**, past a value re-armed DOWNWARD to 647 on 2026-09-02 |
| `test_wiring_gate_devtest` | *"reports a test file that no rule runs"* — an unwired test exists |
| `testmgr_hardcoded_tmp_devtest` | *"new hardcoded /tmp path(s) in compiled test sources"* |

`exit_observable` already has its decision filed:
`decide-what-should-a-shared-gate-do-when-its-watched-number-grows-from-normal-work`.
It is a **decision, not a patch** — 77 rows written without exit-code capture is
a true report, and re-arming the number is the thing the decide- ticket exists to
rule on.

`test_wiring_gate`'s red is likely the `test/c_abi_struct_byval_{main,pxx}.c`
repro found on 2026-09-01 — an unwired regression test for a landed fix whose
ticket is in `done/`. Silencing it with `UNWIRED.txt` would convert a true red
into a false green; the red is correct and belongs to whoever closed that ticket.

**A census that goes red from normal growth is the same shape three times**, and
it is worth noticing that all three live in one job whose verdict cannot
distinguish them from a real defect.

### Cause 3 — one genuine behavioural gap (1 red)

`twatch_host_epoch_devtest`: `governor-change-is-a-new-epoch: governor does not
affect the fingerprint`. Its four sibling checks pass — a hardware change does
open a new bench epoch. So the epoch machinery works and the **fingerprint simply
does not include the CPU governor**, while the guard asserts it should.

Either the fingerprint gains the governor field, or the guard is asserting a
policy nobody adopted. This is the only one of the four that looks like a plain
fix. **Bench numbers across a governor change are exactly the ones that are not
comparable**, which argues the guard is right.

## Ticket coverage

Four of the six are named in no open ticket: `devtest_sync_fold`,
`sync_pending_commit_devtest`, `twatch_host_epoch_devtest`, and
`testmgr_hardcoded_tmp` (named only in an unrelated NilPy ticket). This ticket is
the record for those.

## Not re-derived here, and worth not re-deriving

- **None of the six was edited into failure.** Last touches: 08-30, 09-02,
  08-19, 08-30, 09-01, 08-19. Their *subjects* moved (`sync.sh`, `twatch.py`,
  `testmgr.py`), which is why six went red with none of them changed.
- The 8-full-run streak and the native-GREEN contrast come from the 16:19 report
  at `7c019ef`.
- `2112c18c5` (2026-09-01) already fixed *three* faults in this job, so this is
  the second wave, not the first.

## Suggested order

1. **`twatch_host_epoch`** — the only plain fix; decide whether the fingerprint
   takes the governor.
2. **The sync pair** — one question to the fold guard's owner, then update two
   stale fixtures. Two reds for one answer.
3. **The three censuses** — each needs a ruling, not a patch, and
   `exit_observable`'s is already filed. Re-arming a ratchet to make a job green
   is how a ratchet stops meaning anything.

Note that (1) and (2) alone would take the job from 6 red to 3, and all three
remaining would be censuses correctly reporting drift — which is a materially
different thing for a reader to see than "6 RED".
