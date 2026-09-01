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
