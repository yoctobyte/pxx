---
track: T
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
2. **Close, but say so.** A skip still closes, and the closure is recorded as
   `closed_by: "skip"` rather than as FIXED, so the stub-retirement path and
   any reader can tell "stopped failing" from "stopped running". Keeps the
   anti-immortality property; removes the false claim. **Recommended** — it is
   the same split that fixed the anchor case (separate the two readings rather
   than reclassify the status), and it is additive.
3. **Do not close on skip.** Requires a real pass. Correct in the abstract and
   reintroduces exactly the immortal-entry problem the current rule exists to
   prevent — on a box whose corpus is permanently absent, every such
   regression becomes eternal.

## What is NOT known, and it bears on the ranking

**Nobody knows how often this fires.** A closure by skip is currently
indistinguishable in the record from a closure by pass, which is the defect
option 2 fixes and also the reason the frequency cannot be measured today. So
the honest position is: prio **25**, because there is no evidence of cost — and
option 2 is the change that would let a future reader find out.

Filed at low prio on purpose. It is real, it is small, and it should not
outrank work with a measured cost.

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
of a concept rather than a construct, and it is the strongest argument for
option 2: it is the option that makes the three consistent.

## Gate

Track T's own tooling gate. If option 2 is chosen it is additive to the ledger
(a new key, absent-means-unknown) like `never_passed` before it, so no reader
breaks — but the coordinator should be told, since that is the second ledger
field added in as many days.
