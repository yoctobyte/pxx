---
track: T
prio: 75
type: chore
status: backlog
found: 2026-09-03
found-by: claude-T
owner: ""
blocked-by: []
summary: "tools-devtest#00 is the ONLY red job left in the full tier and has been red in all 8 full runs of 2026-09-02, while native is GREEN — so it is invisible to every lane gating on native or `gate.sh quick`. Its 6 failing guards are FOUR causes, not one: a sync.sh fold-safety refusal added 2026-08-29 trips two guards written before it; three are censuses/ratchets working correctly and reporting real tree drift (one already has a decide- ticket); one is a genuine behavioural gap (the bench fingerprint ignores the CPU governor). Only ONE of the four is a plain bug to fix. **A FIFTH CAUSE APPEARED AFTER THIS CENSUS AND THE SLUG'S COUNTS ARE THEREFORE BOTH STALE** (frank-coordinator, 2026-09-06): `tools/progress_near_devtest.py` builds its corpus from the LIVE board, so its floor assertion measures ONE TICKET'S `summary:` LENGTH (0.138 at 125 summary-tokens, 0.098 at 247, 0.089 at 292, tool code unchanged) and it is red for every session on `make tools-devtest`, which globs `tools/*devtest*.py`. Filed separately as `bug-t-progress-near-devtest-measures-a-ticket-summary-length-so-the-board-turns-the-tool-devtest-red` because it needs a calibration decision. Measured LOCALLY; that it also reds the `#00` job on seven is an inference from the same glob, not a report read. The slug keeps 6/4 because that is what was true on 2026-09-03."
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

---

## Archive measured 2026-09-04 — not a blip, and seven has NEVER passed a full tier

Asked whether the constant full/RED verdict was "a two-run blip or a standing
condition". Measured over the whole `tstate/reports` archive (1825 reports).
Re-ranked 65 → 75 on the result.

**It is standing, and worse than the question assumed.**

- **12 consecutive** full runs with `tools-devtest#00` as the SOLE red, and 17 of
  the last 20. The streak breaks only at 2026-09-03T18:44, where a cmath group
  was also red — and those cleared.
- **seven: 308 full-tier reports, 0 GREEN.** Spanning 2026-08-29T16:51 to
  2026-09-04T03:26. Not one.

### Green full tiers do happen — just never here

| host | full reports | GREEN | most recent GREEN |
| --- | --- | --- | --- |
| **seven** | **308** | **0** | — |
| plexus | 205 | 14 | 2026-08-26T16:08 (`23e3ba7435cc`) |
| xeon | 45 | 4 | 2026-08-03T23:22 |
| borg | 191 | 34 | 2026-07-28T21:27 (retired 08-12) |

So the capability is real and the fleet has lost it: **the last green full tier
anywhere was plexus on 2026-08-26**, eight days ago. seven began running fulls on
08-29 — three days after that — and has never produced one.

### What that costs, precisely

`pin_is_green` requires a `full` run with no RED tier. Every pin since has been
cut on seven. So **since seven became the pinning box, a fresh rollback target
has been structurally unobtainable** — not unlucky, unobtainable. That is exactly
why `trackt pinstatus` still answers *"last pin T found fully green: v354
(19d5d9c7)"* from 2026-08-19, and why the recovery half of the fast-pin trade
(`devdocs/dev/track-t.md:151` — "a bad pin is recovered, not prevented") has had
no target for two weeks while three pins were cut through it.

**This job is the whole of that gap.** In 12 of the last 12 runs it is the only
thing standing between the tree and the first fresh fallback since v354.

### And it sharpens Cause 1's host-specificity

frankZ measured that four of this job's guards — `twatch_timeout_staleness`,
`twatch_timeout_verdict`, `twatch_verify_request`, `verify_assertions` — **pass on
plexus and fail on seven in the same `make tools-devtest` invocation**. The
hypothesis offered then was that seven is the box where a live watcher exists, so
guards asserting over live watcher state behave differently here.

0-of-308 on seven against 14-of-205 on plexus is consistent with that and raises
it well past a guess: **the guard set that can only fail where a live watcher runs
is failing on the only box that runs one.** Still a hypothesis — the falsifying
test is a watcher-free run on seven, which nobody has done — but it is now the
leading one, and it predicts that fixing the four host-specific guards is what
turns 0-of-308 into a green tier.

---

## Two corrections to the section above — 2026-09-04, claude-T

Both are mine, both were caught by the coordinator, and both make the case
stronger rather than weaker.

### 1. "three pins were cut through it" was wrong — it is 52

`git log origin/master --grep='chore(stable): pin' --since=2026-08-19` counts
**52** pin commits since v354's green, from `0c189b6f0` (v353, 08-19) to
`ce63beeeb` (v403, 09-04). I wrote three because I was counting the three I cut
myself and stated it as though it were the whole gap.

**The window was the defect, not the arithmetic.** A figure whose population is
unstated reads as a claim about everything, and this one understated the cost by
a factor of seventeen: fifty-two pins have been cut with no fresh rollback target
available to any of them.

### 2. The `exit_observable` numbers here were stale within hours

This ticket quoted **676 of 727 = 92.98%**. A second session quoted **797 of 849
= 93.88%** against a **92.69%** cap in the same hour, and the coordinator
correctly declined to reconcile them rather than guess.

Re-ran the guard. **The other reading is right and mine was old** — same job,
same host, no population split:

```
PASS the cross-target differential population is intact … 849
FAIL and the stdout-only SHARE has not grown past its measured value
     797 of 849 = 93.88%   (re-armed DOWNWARD 2026-09-02 at 647 of 698 = 92.69%,
     after capping five arm32 leak rows rather than ratifying the drift;
     was a COUNT capped at 531, which the corpus outgrew while getting better)
PASS and that bound is tight — one more uncapped row would breach it
     93.8824% vs 92.6934%
```

The denominator went 727 → 849 between the two readings. So **a number quoted
from this guard is stale in hours**, which is itself the finding: anyone citing it
must name the run, not just the value.

And the guard's own history is the argument of this ticket in miniature. It was a
COUNT capped at 531; the corpus "outgrew it while getting better", so it was
re-expressed as a SHARE and re-armed *downward* to 92.69% by capping five arm32
rows "rather than ratifying the drift". **It has already survived one round of the
exact temptation — re-arm to green — and chose the harder option.** Its final
check knows the bound is tight to one row. That is a working instrument, and its
red is the tree's answer, not its own defect.

### Also now stale above: the pin version

The section above was written when the pin was v401. **v402 (`80ecb94023eb`) and
v403 (`c31d03b202da`, "the first post-flip pin") have landed since**, and v403 is
what the tree carries. The argument is unchanged and the count is worse: two more
pins through the same gap.

## Two independent data points from one day, 2026-09-04 — and they point OPPOSITE ways

Reported by frankz-43, which hit both while doing unrelated work, and recorded
here rather than in a message because a coordinator's memory is not a ranking
input.

- **`tools-devtest#00` HID work that was done** — one job name kept an unmoved
  verdict in front of five guards that had been closed. The board said one red;
  five things had been fixed behind it.
- **`lib-test#00` INFLATED work that did not exist** — four job names turned out
  to be one construct. `lib-test#crtl_reachability` IS `lib-test#00`, the same
  job as the three `lib_synapse*` entries. A backlog read four times its real
  size, and nobody should pick those up as separate work.

**Both write-ups were wrong, in opposite directions, from the same property.**
That is the argument for ranking this above a normal chore: a name that
over-reports and a name that under-reports are not two bugs, they are one
ambiguity read twice, and neither reading announces itself. An unmoved verdict
looks like a live red and a repeated job name looks like distinct work.

**This is NOT a regression of
[[bug-t-a-job-named-after-its-first-source-file-cannot-name-its-failing-step]],
and reopening that would be wrong.** That ticket fixed ROUTING — `track:` is now
derived from the failing step's own sources — and it *structurally refused* to
make the slug step-derived, for a reason that still holds: the slug is both the
dedupe key and the close key, and `close_stub_tickets()` recomputes it from the
job at a moment when no step is in scope, so a step-derived slug would leak
every stub open. It also named its own residue honestly — *"ownership remains
unrecoverable"*. What frankz-43 hit is a DIFFERENT residue of that same
deliberate decision: not "which lane owns this red" but **"how does a reader
tell that four job names are one job, or that one job name is five verdicts?"**
Nobody owned that question, which is why it cost two write-ups before anyone
wrote it down.

### A third instance, same day, third session — and that crosses a threshold

`regression-test-core-test-stackless-gen-2` carried `track: P`, guessed from the
failing step's path and never corrected. It was handed out as live Track P work;
it was already fixed, and closed 2026-09-04 after re-verifying against the job's
own comparison in `Makefile:10887` rather than against the step the ticket named.
Noted on its `done/` entry so the guess is not read as a finding.

So the tally for 2026-09-04 is **three instances, from three sessions that were
each doing something else**: claude-T's `tools-devtest#00`, frankz-43's
`lib-test#00`, and this one. CLAUDE.md's own counting rule is that two is a
smell and three is a design flaw, and this is three — in one day, none of them
looked for.

**The property that makes it a design flaw rather than three chores is that
nobody notices any single one.** Each instance is individually plausible: an
unmoved verdict looks like a live red, a repeated job name looks like distinct
work, a guessed lane looks like a routing decision someone made. None errors,
each answers, and each is only visible from outside the session that hit it.
Three sessions each found one and none of the three could have found the other
two. That is the argument for fixing the naming rather than continuing to catch
the instances — catching them does not scale, because the catch requires a
vantage point no single session has.

Recorded by the coordinator, which is the only seat that saw all three, and
banked here rather than kept as context: the count is the finding, and a count
held in a session's memory is not a ranking input.

---

## Cause 3 FIXED, and my diagnosis of it was wrong — 2026-09-04, claude-T

I wrote above that *"the bench fingerprint omits the CPU governor while the guard
says it should include it"* and called it "the only plain fix". **That was
wrong. `governor` is in `HW_KEYS` and has been.** The defect was in the guard,
and it is two defects:

```python
a = dict(hw); b = dict(hw, governor="performance")
fa = sha256(json.dumps(a, sort_keys=True))[:12]
fb = sha256(json.dumps(b, sort_keys=True))[:12]
assert fa != fb, "governor does not affect the fingerprint"
```

**1. It hard-coded `"performance"` as the changed value.** seven's governor *is*
`performance` — measured, `/sys/…/cpu0/cpufreq/scaling_governor` → `performance`.
So `b == a`, the hashes matched, and the assert fired **accusing the code**. The
guard could not distinguish *"I failed to change anything"* from *"the code
ignores my change"*, so it reported the second.

**This is one of frankZ's four host-specific guards, explained.** It passes on
plexus and fails on seven in the same `make tools-devtest` invocation for one
reason: seven's governor happens to equal the literal the fixture names. Nothing
about a live watcher — the live-watcher hypothesis does not cover this one, and
that is worth knowing before the other three are assumed to share a cause.

**2. It re-implemented the fingerprint instead of calling it.**
`sha256(json.dumps(hw))` over the whole dict is not `fp_of_hardware()`, which
filters to `HW_KEYS` and quantises memory. So the hand-rolled hash was never the
thing under test: **it could have passed while `fp_of_hardware` ignored the
governor entirely**, which is the only failure this check exists to catch. A
guard that reimplements its subject validates the author's intention.

### Fix and its control

Pick a value that DIFFERS from the live one, and ask the real function:

```python
live  = hw.get("governor")
other = "powersave" if live != "powersave" else "performance"
fa = twatch.fp_of_hardware(dict(hw, governor=live))
fb = twatch.fp_of_hardware(dict(hw, governor=other))
```

Verified by discrimination, not by passing: with `governor` removed from
`HW_KEYS` in a scratch copy the guard **FAILS** —
`governor does not affect the fingerprint (performance -> powersave both hash
bf64e064d6aa)` — and with it present, passes. The old guard could not
discriminate on seven at either setting.

`tools-devtest#00` is now **5 red, three causes**. The remaining five are the
sync pair (Cause 1) and the three censuses (Cause 2), and no census should be
re-armed to clear it.

### Note on the toolchain gap, separately

While here: `host_hardware()` already records `kernel` and `gcc` and both are
fingerprinted. **`qemu-*` versions are captured nowhere** — and seven runs qemu
8.2.2 on every arm against plexus's 10.2.1, which is a standing environmental
cause for "red on seven, green locally". That is a real gap, it is `tstate/`, and
it is a separate ticket from this one; the fingerprint machinery to hang it on
already exists and already has the guard above protecting it.

---

## Cause 1 FIXED — both reds, one answer, and the ticket's own reading of it was wrong — 2026-09-05, frankZ

The section above says of the sync pair:

> **The refusal is almost certainly right and the guards are almost certainly
> stale** — but that is a judgement about whether the fixture's mid-rebase state
> is one a caller should ever reach, and it belongs to whoever owns the fold
> guard.

**The refusal is right and the guards were not stale.** There was no judgement to
route to anyone, and nothing about the fixture's mid-rebase state: the two tests
were failing for a reason that has nothing to do with what either asserts.

### The cause

`sync.sh` was **stranding mid-rebase because it had no git identity**, and the
fold refusal is what a stranded rebase looks like from one layer up.

Neither test supplies one to `sync.sh`. Both supply one to **themselves**:

```python
["git", "-c", "user.name=devtest", "-c", "user.email=devtest@example", ...]
```

That is per-invocation, so it covers the fixture's own commits and **not the
separate `sync.sh` process**, which inherits nothing from it. A rebase commits.
So on a host with no ambient identity, `sync.sh` dies inside
`rebase --continue`, leaving `.git/rebase-merge` behind — and `sync.sh` then
reports `still mid-rebase after resolution — refusing to amend`, which is TWO
LAYERS above `unable to auto-detect email address`.

**seven has neither `~/.gitconfig` nor `/etc/gitconfig`** — measured. plexus has
one. That is the whole of the host-specificity: **the test was passing on plexus
because of the box, not because of the tree**, and a fixture that silently
depends on ambient host config is testing the box.

Note what this does to the leading hypothesis recorded above. The live-watcher
theory does not cover these two either — that is now **two** of frankZ's four
host-specific guards explained by something else (the governor literal was the
first). The remaining two should not be assumed to share a cause with anything.

### Two fixes, and the second one is the one that matters

**1. The fixtures now hand `sync.sh` an identity of its own**, via env rather
than `-c`, because env is what crosses a process boundary. Both files.

**2. `sync.sh` refuses UP FRONT when it has no usable identity** — before it
touches anything. This is the real repair and it is not test-only:

> `sync: no usable git identity -- refusing to START, because a rebase that
> cannot commit strands the tree mid-rebase instead of failing cleanly. Nothing
> has been touched.`

Every lane runs this script. A host that cannot commit should learn so in one
line, not by having its tree stranded and then reading a fold-guard message that
accuses the wrong thing. `git var GIT_COMMITTER_IDENT` is the probe, not a
config lookup: it fails both when the fields are unset AND when the
auto-detected address is unusable (`seven@seven.(none)`), which is the condition
git actually refuses on.

The fold refusal from `f81498db8` is untouched. Nothing was loosened.

### Controls, both directions

Measured, not reasoned — and the first one caught a dead row of my own.

- **Guard removed from `sync.sh`, fixture unchanged:** 4 of 5 new rows go RED
  (`rc=1` with no message, `rebase-merge` left behind, HEAD detached at `HEAD`,
  and the clean-sync row fails too). With the guard: all green.
- **That control initially showed `rc=0` and I had to fix the fixture, not the
  guard.** The section-3 world had no divergence, so `sync.sh` fast-forwarded,
  never needed to commit, and never needed an identity — three rows including
  the one I had labelled *THE LOAD-BEARING ONE* were passing trivially and
  **could not have failed.** The fixture now forces a real rebase by having both
  clones write different content to `gen/board.md`. A guard that cannot fail
  prints PASS, and mine did.
- **Both tests run green under a synthetic seven** (`HOME` empty,
  `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, every `GIT_*_NAME/EMAIL`
  unset) **and under a normal plexus.** Before the fix, that same environment
  reproduces seven's red here — which is what established the cause rather than
  matching a message.

`tools-devtest#00` should now be **3 red, one cause**: the three censuses of
Cause 2, each of which needs a ruling and not a patch. No census was re-armed.

**Not verified from here:** that seven's run agrees. This box is not that box,
and the claim above is "the condition seven has, reproduced here, is fixed here".
The confirming instrument is seven's next full tier.
