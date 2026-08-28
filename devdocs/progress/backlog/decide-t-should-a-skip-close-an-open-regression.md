---
track: U
prio: 25
type: decide
blocked-by: []
summary: "reg_open counts red -> skip as FIXED, so a regression closes when a box merely STOPS RUNNING the job — the mirror of the skip-as-last-good bug, pointing the other way. It is a deliberate existing trade (the alternative pins a regression open forever on a box that cannot run the job), so it is a policy call, not a defect. Split out of 0dec0194a rather than bundled, because a policy change smuggled in behind a bug fix is how the trade would have been lost without anyone deciding it."
---

# Should a SKIP close an open regression?

- **Type:** decision (Track T policy). Not a defect — the current behaviour is
  deliberate and documented.
- **Filed 2026-08-28 by Track T (pxx-a5)**, split out of
  [[bug-t-a-skipped-job-is-passlike-so-it-becomes-a-false-last-good]]
  (`0dec0194a`) at the coordinator's directive, because the note that ticket
  carried — *"its own ticket if the false fixed is ever seen to cost
  something"* — **had no observer.** A trigger nobody is assigned to watch is
  not a trigger, and `done/` is where findings stop being read.

## The behaviour

`reg_open()` treats `skip` as PASSLIKE, so a job going **red -> skip** closes
its open regression and is reported as FIXED. Its own docstring says so and
says why:

> A `skip` is PASS-LIKE here: it does not gate, and red -> skip still closes an
> open regression, because a box that legitimately cannot run a job must not
> hold a regression open forever. It is NOT proof a regression is fixed, so a
> cascade whose jobs only ever SKIP still closes wrongly — a known residual.

So the cost is already named in the code. What has never been decided is
whether it is the right cost.

## Why it is a decision and not a bug

It is the **mirror** of the bug just fixed, pointing the other way, and the two
have opposite failure modes:

| | if `skip` counts as pass | if it does not |
| --- | --- | --- |
| **anchor** (fixed in `0dec0194a`) | a false regression over innocent commits | correct |
| **closing** (this ticket) | a regression closes without being fixed | a regression is pinned open forever on any box that cannot run the job |

The anchor case had a strictly-better answer, so it was a bug and got fixed.
This one does not: both directions lose something real, which is exactly what
makes it Track U-shaped even though it lives in T's file. Hence `decide-`.

**It was deliberately NOT bundled into `0dec0194a`.** Changing it there would
have been a policy change smuggled in behind a bug fix — the trade would have
been reversed without anyone deciding it, and the docstring recording the
reasoning would have been quietly falsified.

## Options

1. **Keep it.** A skip closes. Cost: a regression can vanish without being
   fixed, and nothing says so. Cheapest, and the status quo has not visibly
   burned anyone — though see the note on observability below.
2. **Do not close on skip.** Requires a real pass. Correct in the abstract and
   reintroduces exactly the immortal-entry problem the current rule exists to
   prevent — on a box whose corpus is permanently absent, every such
   regression becomes eternal.

## What is NOT known, and it bears on the ranking

**Nobody knows how often this fires.** A closure by skip is currently
indistinguishable in the record from a closure by pass — which is simultaneously
the defect and the reason its frequency cannot be measured. Counting it needs
[[chore-t-record-how-a-regression-closed]], which is split out precisely so this
question is not blocked behind its own instrument.

Filed at low prio on purpose: real, small, and it should not outrank work with a
measured cost.

## What was split out, and why it is not an option here

An earlier draft of this ticket listed a third option — *"close, but record
`closed_by: skip`"* — and recommended it. That was a category error, caught by
the coordinator: recording how a closure happened is **strictly additive and
loses nothing in either direction**, so it is not a horn of the dilemma. It is
the instrument that makes the dilemma measurable. As written, this was a
decision whose deciding data the same ticket proposed to gather.

It is now [[chore-t-record-how-a-regression-closed]] [T, p30], and it should be
done whether or not this question is ever answered.

## Track U, not T — and that is a deliberate correction

Filed originally as `track: T`, on the reasoning that Track T self-governs its
own tooling. That was wrong, and the queue said so: **12 of the 13 `decide-*`
tickets are `track: U`**, including [[decide-t-refuse-unscoped-pattern-kills-in-a-hook]],
which is likewise a decision about Track T's own tooling. The precedent is
clear and it is the right one — **U is about who DECIDES, not who owns the
file.**

The consequence of getting it wrong was concrete rather than cosmetic: at p25
behind T's p55/p50/p45, a `track: T` decision would never be reached, and
never-reached is not neutral here. It silently selects option 1, which is the
status quo — a decision made by queue position instead of by judgment. That is
the same shape as the trigger-with-no-observer that caused this ticket to be
split out of `0dec0194a` in the first place.

## Sibling

[[bug-t-a-skip-that-cannot-say-why-is-a-pass-in-the-verdict]] (T, p50) is the
**third** direction of the same confusion, and the three are worth reading
together — but they are genuinely distinct mechanisms with distinct fixes, and
merging them would produce one ticket that is three half-descriptions:

| ticket | where `skip` is mistaken for `pass` | fix |
| --- | --- | --- |
| `bug-t-a-skipped-job-is-passlike…` (done, `0dec0194a`) | choosing the last-good **anchor** | anchor on execution |
| this one | **closing** an open regression | record how it closed |
| `bug-t-a-skip-that-cannot-say-why…` (p50) | the **run verdict and its report** | record a reason and a skip count |

One root — *a skip means the job did not run, and "did not run" is not
"passed"* — reached through three independent code paths, none of which knows
about the others. That is the `normalise-dont-special-case` smell at the level
of a concept rather than a construct — and it is the strongest argument for
doing [[chore-t-record-how-a-regression-closed]] regardless of how this is
decided, since making the record honest is what the three paths have in
common.

## Gate

None — this is a decision, not a change. Whichever way it goes, the resulting
work is re-filed into Track T with T's own tooling gate, per the rule that a U
item which turns out to be plain work once decided goes back to the owning
lane.
