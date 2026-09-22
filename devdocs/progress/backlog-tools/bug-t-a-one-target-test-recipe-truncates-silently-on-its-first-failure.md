---
slug: bug-t-a-one-target-test-recipe-truncates-silently-on-its-first-failure
track: T
type: bug
prio: 60
status: backlog
found: 2026-09-22
found-by: franks-5b
owner: ""
blocked-by: []
summary: "A make target whose recipe is one long list of test lines ABORTS AT THE FIRST FAILURE and runs none of the rest, and NOTHING IN THE OUTPUT SAYS HOW MUCH DID NOT RUN. `make -k` does not reach it -- it continues past failed TARGETS, and this is one target. So any standing red converts the tail of that target into silent non-coverage for every seat that runs it, and a seat reading RED believes it gated. MECHANISM, not a row: this springs whenever a one-target recipe carries a red, whoever left it and wherever it sits; the earlier the red, the more is lost. Measured 2026-09-22 on test-nilpy (Makefile:511, recipe 512-7189, 6614 recipe lines): a red at Makefile:4718 left 2470 lines -- 37.3% -- unexecuted, with the run reporting only the one mismatch. The remedy is a harness property (run all, report a tally) and does NOT require narrowing or removing any test. THE TERRITORY BEHIND THE RED IS MEASURED AND GREEN: a `make -i` run the same day reached the end of the recipe with EXACTLY ONE failure, the red itself -- so this asks for a harness that can TELL you that, not for an investigation of what is hiding."
---

# A one-target test recipe truncates silently on its first failure

**This is a finding about what a gate MEANS, not about any particular red.**
State it as the mechanism, because the row that exposed it will be settled and
the mechanism will not.

## The mechanism

`make` aborts a recipe at the first command that exits nonzero. Where a test
target is **one target whose recipe is a long list of test invocations**, that
abort discards every remaining line. The run reports the failure it hit and
says **nothing** about the lines it never reached — there is no tally, no
"stopped at", no count. To learn how much was skipped you have to find the
target in the Makefile and count recipe lines.

**`make -k` does not help.** It continues past failed *targets*. A single
target with 6,000 recipe lines is one target, so `-k` aborts at exactly the
same place. `make -i` does run the remainder, and is what produced the coverage
number below, but it is not what anyone gates with.

## Why it is worse than an ordinary red

**A red is supposed to be the loud case.** Here the red is loud and the
truncation is silent, so the loudness of the one masks the absence of the
other — **nobody checks coverage on a run that already told them something.**
It is a guard that cannot fail wearing the shape of a guard that did
(frankuser's phrasing, 2026-09-22).

The gradient is the nasty part: **the earlier the red, the more coverage is
lost**, so the worst case is a standing red near the top of the recipe, which
is also the case least likely to be urgently fixed because everyone has learned
to recognise it.

## Measurement, with its population

`test-nilpy`, 2026-09-22, compiler `464ddd6c2b02`:

| | |
| --- | ---: |
| target | `Makefile:511` |
| recipe | lines 512-7189, **6614** recipe lines |
| failure at | `Makefile:4718` |
| lines never executed | **2470** |
| coverage lost | **37.3%** |
| failures reported by the run | 1 |

**Do NOT quote this as "half the suite".** An earlier statement of mine said
"more than half", from an assumed denominator -- I took the span from the abort
line to the target's end and never measured the recipe's length. The run that
aborted got 62.7% of its coverage. The number is bad enough true.

## THE TERRITORY BEHIND THE RED IS MEASURED AND IT IS GREEN

**Run under `make -i` on 2026-09-22 (compiler `c0d363f340c8`): 6709 lines,
reached the end of the recipe, EXACTLY ONE failure — the `atan2` row itself.**
Everything in the 37% that no ordinary run reached that day passes.

That is worth stating because it changes what this ticket asks for. It is not
*"a red hides unknown territory"* — the territory is known and clean. It is
*"the harness cannot TELL you that, and will not tell you next time either."*
Clearing the one red restores the full gate for everyone, so the decision that
unblocks it is cheaper than the truncation makes it look, not scarier.

**Re-take this line when the recipe changes.** It is a measurement of one tree
on one day and it is the kind of fact that silently stops being true.

**And the affected population is UNMEASURED.** `.claude/hooks/no-full-suite.sh`
denies `make test*` by default, so running this target at all requires setting
`PXX_ALLOW_FULL_SUITE=1` deliberately. The set at risk is "seats that ran the
full NilPy suite while a red stood", which may be very small. **Nobody has
counted it and this ticket does not claim a number.**

## What would fix it, and what would not

**Fix:** make the harness run every line and report a tally — pass/fail counts
and an explicit "N lines not run" when it stops early. That is a property of
the harness and needs no test narrowed, removed or weakened.

**NOT a fix, and specifically refused:** narrowing or removing whichever test
currently reds. That is a **loosening**, which is the owner's call however
small the diff, and where the seat proposing it would be unblocked by it, it is
disqualified twice over. Recorded here as a refusal rather than left as an
omission, because the next reader otherwise sees an obvious one-line fix and no
reason it was not taken.

## The row that exposed it, for the record only

`test_nilpy_math_atan_and_atan2_bit_for_bit` has been red since `6b8b45af4`
(2026-09-22 09:54) — 20 of 272 rows moved by exactly 1 ULP, histogram {1:20},
zero worse, deliberately left standing with the reasoning in the LOGBOOK. It is
the **occasion**, not the cause. When it is settled this ticket stays true, and
the next standing red springs it again.
