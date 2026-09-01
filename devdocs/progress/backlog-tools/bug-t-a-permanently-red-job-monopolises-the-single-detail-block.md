---
slug: bug-t-a-permanently-red-job-monopolises-the-single-detail-block
title: "A permanently-red job wins the one detail slot, so NEW reds ship without detail"
track: T
prio: 55
type: bug
status: new
blocked-by: []
found: 2026-09-01
found-by: frank-coordinator
owner: unassigned
summary: "A tstate report carries at most ONE detail block (job_reason_devtest.py:150, twatch.py:2022) and fills it from `## first failure:`. Because a standing red is present in every run, it keeps winning that slot, so genuinely NEW reds ship with a truncated tail and no detail — starved of it exactly when they are the news. Live case: reports/20260901T155512Z-66cda21-seven.md has 7 failures, one detail block, and it went to test-threads#exception_threads_race (red in 5 of 5); the four NEW dynarray reds each got a tail cut mid-word at `| p`. Three sessions then spent an afternoon inferring what the log on seven said plainly."
---

# A standing red monopolises the one detail block

Found while three sessions reasoned about a four-target red whose cause was one
`ssh` away.

## What happens

The report keeps **one** detail block and fills it from the `## first failure:`
slot. Selection does not consider whether a failure is new. A job red in every
run is therefore *always* a candidate and *usually* first, so it wins
permanently — and the reds that changed this run, which are the only reason
anyone reads the report, get a truncated tail instead.

**The one-log limit is deliberate and documented** (`job_reason_devtest.py:150`,
`twatch.py:2022`) and is not the defect. The **selection** is: a constant
crowding out the variable.

## Measured instance, 2026-09-01

`reports/20260901T155512Z-66cda21-seven.md` — 7 failures, 1 detail block, spent
on `test-threads#src:test/test_exception_threads_race.pas`, red in 5 of 5 recent
full runs. The four `test_managed_dynarray_field_leaks.pas` reds — all NEW that
run, on four targets — each got a tail cut mid-word at `| p`.

The answer they needed was one line in
`/tmp/testmgr-<id>/test-aarch64#147.log`: `assert_no_leak[...]: LEAK — live=111
exceeds 50`. Without it, three sessions produced two wrong root causes (an
`expect_same` counter difference; a load-shaped flake) and one wrong
exculpation, over about four hours.

## The fix, and the shape to avoid

Prefer a **new** red for the detail slot; fall back to first-failure only when
nothing is new. Anything that ranks by position rather than by novelty
reintroduces it.

**Do not fix this by raising the limit.** The limit is a deliberate bound on
report size with its own devtest. The question is which failure earns the slot.

## Related

Same family, one layer down and already written up: the reports list NEW reds,
so grepping them for a standing red returns near-empty whether or not it is red
— `debugging-playbook.md`, "an instrument can be anti-correlated with the truth
of the question" (`3624bc97d`).

## The information was not lost — it was routed to the artifact nobody reads after a red

Found by frank-coordinator 2026-09-01, verified here before recording.

The four-target dynarray red cost three sessions and an ssh to the host to
identify its failing assertion. **A ticket auto-filed by twatch at the moment of
the red already named it**, in its heading:
`regression-test-aarch64-test-managed-dynarray-field-leaks` — exact sha, exact
step (`4/5`), and `tools/assert_no_leak.sh` named outright. Prio 70, sitting in
`backlog/` the whole time.

**Why it went unread is a mechanism, not a lapse.** Everyone was reading the
tstate REPORT, and the report and the ticket derive their identifying string
from different places:

- the report's rows carry `src`, from **`testmgr.py:2009` `extract_src()`**,
  which lists source-ish paths found in the log and is itself truncating
  (`twatch.py:4684` documents it: two paths, then `+N`);
- the auto-filed ticket's heading carries the failing recipe line, from
  **`twatch.py:4694` `step_fields()`**, which reads `step_i`/`step_line` — the
  step that actually went red.

Two artifacts generated from the same run, naming different tools for the same
failure, **with nothing on either marking it as partial**. The one everybody
opens after a red is the one naming the wrong tool.

This sharpens the finding above rather than replacing it. The single detail
block went to a standing red, so the report carried no diff for the four new
reds — but the auto-filer had already extracted the failing step for exactly
those rows. **So something downstream already computes the thing the report is
missing.** The fix is therefore cheaper than it looked: the report should print
the failing step for a NEW red, from `step_fields()`, which is already there.

### A third truncation, in the same path, fixed on the way past

`twatch.py` built the heading with `hstep[2][:56]` and appended the closing
backtick after. This step is exactly 56 characters up to the `5` of `50`, so the
filed heading read `... managed_dynarray_field 5` — a plausible bound, off by a
factor of ten, in the one line everyone reads. The bound was never 5 (`git show
0d3d061121a7:Makefile` and its parent both say `50`; one commit ever touched
it). Cap is now 120 with a visible `…`, asserted both ways: the 108-char step
survives whole, a 200-char one still truncates and shows it.

**All three truncations here are silent.** `extract_src` at least appends `+N`.
The other two produced well-formed output that read as complete.
