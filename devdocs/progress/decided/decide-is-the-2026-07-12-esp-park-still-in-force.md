---
slug: decide-is-the-2026-07-12-esp-park-still-in-force
track: U
prio: 65
type: decide
status: open
found: 2026-08-30
---

# DECIDE: is the 2026-07-12 ESP park still in force? 23 ranked tickets and a staffed agent depend on it

Raised by frankB, which found the park while working an ESP ticket **I dispatched it to**,
and said so on the record rather than burying it: *"that is a user priority call and not
something a thin queue should quietly erode."* It is right, and I cannot settle it.

## The two facts that disagree

**The park.** *"ESP parked (user 2026-07-12): Pascal has prio."* Recorded as a **comment on a
`prio:` field in one `done/` ticket**, and restated in the prose of one backlog ticket. That
is its entire existence.

**The campaign.** CLAUDE.md's Track S section describes ESP as a live lane with a stated
primary target, and cites a **later** owner ruling — xtensa is primary, riscv32 is what works
today. `~/frank.sh` gained a dedicated `frankS` on **2026-08-29**, added by the coordinator
because *"the ESP32/SoC campaign had 12 ranked tickets and no agent."*

## Why I am escalating instead of deciding

A July park and an August campaign description are not obviously reconcilable, and the
tie-breaker is your intent, not anything in the tree. Both readings are defensible:

1. **The park was superseded** by the later xtensa ruling and by S being surfaced as a formal
   lane. Then everything done tonight is correct and the stale comment should be struck.
2. **The park still stands** and Pascal still has priority. Then the fleet spent a night on a
   parked campaign, 23 ranked rows should be re-priced down, and frankS should be stood down
   or re-lane.

I am not guessing between them. Guessing costs a night of work in one direction or an
incorrectly-parked campaign in the other.

## What this cost while unresolved, stated plainly

I staffed frankS onto ESP, dispatched frankB to `feature-dns-esp-backend`, and **filed two
new ESP tickets myself tonight at p70 and p65**. If the park stands, all of that was me
eroding a user priority call, and none of it was deliberate — because **the park has no
mechanism.** 23 ESP/xtensa rows are ranked and dispatchable right now.

## The general defect, which is fixable regardless of the answer

This is the **second** instance today of a user decision enforced only by a number:
`bug-nilpy-except-tuple-binder` was held on 2026-08-14 and priced to 20, and a bulk re-triage
on 2026-08-25 swept it to 55 — it has ranked ever since. Repaired by giving it the `NOT
DISPATCHABLE` marker, which survives re-pricing because it is not a price.

**A park recorded as a prio comment is not a park.** Whichever way this ruling goes, if you
park a *campaign* again the durable form is the marker (or an explicit `gated-by:` on a
`decide-`), not a number and not a comment — because a comment on one ticket cannot reach the
other 22, and the ranker never reads it.

## What I need

One word. *Superseded* → I strike the stale comment, keep the lane, and note the
supersession. *Still parked* → I re-price the S rows, stand frankS down, and record it where
the ranker can see it this time.



## Chronology, added 2026-08-30 — and it sharpens the fork rather than settling it

frankB supplied the ordering; I checked the middle term against a source it did not choose,
and found a fourth data point it had not claimed.

| when | what |
| --- | --- |
| **2026-07-12** | the park: *"ESP parked (user 2026-07-12): Pascal has prio"* |
| **2026-08-02** | ESP work actively progressing — see below |
| later | CLAUDE.md's Track S written as a live lane, *"Primary target is xtensa (the user's S2/S3 hardware); riscv32 (C3) is what works today"* (undated) |
| **2026-08-29** | the coordinator adds a dedicated `frankS` to `~/frank.sh` |

**frankB's point, and it is the sharpest statement of the ambiguity:**

> a target-priority ruling is not the same as a work-priority ruling, and *"when we do ESP,
> do xtensa first"* is entirely consistent with *"don't do ESP yet"*.

So the later xtensa ruling does **not** by itself supersede the park. It answers a different
question. That is the strongest argument that this genuinely needs you rather than a
coordinator reading.

**Precision on the middle row, because the distinction matters.** frankB cites a *2026-08-02
user correction that xtensa is the primary ESP target*, recorded in its own ticket — I am
relaying that on its citation and have **not** independently found the ruling text. What I
did find, in files neither of us picked for this purpose, is that **ESP work was actively
progressing on 2026-08-02**: `feature-esp-hardware-flash-validation.md` — *"Everything except
the board is now in place (2026-08-02)"* and *"The peripheral half is unblocked too
(2026-08-02, later)"*; `feature-a-promoint-variant-esp-targets.md` carries a dated
2026-08-02 diagnosis.

**Which is a fourth fact and possibly the most useful one: the park was already not being
observed three weeks after it was made, by sessions that had nothing to do with tonight.**
Tonight's staffing is the largest instance, not the first. That is consistent with either
reading — the park was understood as superseded, or it has been invisible to every session
since the day it was written — and those two are indistinguishable from the tree, which is
exactly why this is a U ticket.

## What this does not change

Still one word. But if the answer is *still parked*, the follow-on is bigger than re-pricing
23 rows: work has been landing against a parked campaign for seven weeks, and some of it is
in `done/`.
---

## EVIDENCE (frankB, 2026-08-30) — the park was not superseded. One commit deleted it.

Appended by frankB, not the ticket's author. **This is evidence, not a change to the
recommendation** — the fork above stands and the call is still the owner's. It is here
because it answers a question the ticket poses as unanswerable, and the owner reads this
page. Specifically, it addresses the chronology section's closing judgement that the two
readings are *"indistinguishable from the tree"* — they are distinguishable, and `git log`
is where the difference is.

I went looking to verify my *own* citation (the 2026-08-02 xtensa ruling), since the
coordinator relayed it on my word and labelled it unverified. It verifies — the dated user
attribution appears independently in `done/feature-xtensa-stack-args-over-6-words.md`, both
in its frontmatter and in a dedicated section. But the search turned up the park's actual
history, which nobody had looked at.

### The park had a real mechanism, and it was destroyed by a bulk re-price

`git log --follow` on the ticket the park is cited from:

| commit | date | what happened to the park |
| --- | --- | --- |
| `ad649f55f` | **2026-07-12** | *"tickets: park ESP family (user: Pascal has prio)"* — applied across **three** tickets, each re-priced with the ruling recorded in the `prio:` comment |
| `ab584382e` | **2026-08-25** | *"tickets: apply the approved re-triage — prio now spans 3-88"* — `prio: 30  # ESP parked (user 2026-07-12)…` **replaced by bare `prio: 20`**. Comment text deleted. |

So the park was never "recorded in one `done/` ticket". It was applied deliberately to a
family, with the reason attached to each number, and **a bulk re-triage six weeks later
stripped it**. The re-triage commit message does not mention ESP; nothing about it was a
decision to unpark anything.

### Where the ruling survives is the tell

Of the three tickets that carried it:

| ticket | state today | park comment |
| --- | --- | --- |
| `bug-esp-emit-obj-proc-fixup-non-iram` | `done/` | **KEPT** |
| `bug-esp-idf-heap-linux-mmap-ecall` | `done/` | **KEPT** |
| `feature-pal-esp-posix-fd-semantics` | `unfinished/` — **live** | **DELETED** |

**The park survives in both tickets where it can no longer act, and was deleted from the
only one where it still could.** Not because anything targeted it: a re-triage re-prices
*open* tickets, and `done/` tickets are not re-priced. The enforcement was destroyed exactly
where it was still load-bearing and preserved exactly where it was inert. That is why it
reads today as a fossil in `done/` — the live copy was removed on 2026-08-25.

### This is the same commit that swept the NilPy hold

`ab584382e` also carries `bug-nilpy-except-tuple-binder-is-typed-by-the-first-arm-only`:
`-prio: 20` → `+prio: 55`. **One commit erased two user rulings.** They are not two instances
of a class discovered on the same night; they are one event with two victims, and the class
has exactly one known cause: *a user decision whose only enforcement is a number, met by a
process that rewrites numbers in bulk.*

### What this does and does not settle

It does **not** decide the fork — whether ESP should be worked now is still the owner's call,
and reading 1 (superseded) can still be the right answer on the merits.

It does remove one of the two readings *as a description of what happened*. The park was not
superseded by a later decision; no decision touched it. And "nobody ever saw it" is too kind:
the ruling sat intact in a live ticket's frontmatter from 2026-07-12 to 2026-08-25, which
includes the 2026-08-02 ESP activity the ticket cites — so ESP work proceeded for six weeks
*while the park was present and readable*, and then the record of it was deleted mechanically.
The erosion has two distinct phases, unobserved and then unrecorded, and only the second is
about the missing mechanism.

**If the ruling is that the park still stands**, the repair is not just re-pricing 23 rows: it
is that a `prio:` comment is not a mechanism, and `ab584382e` is the proof — the same commit
would silently undo it again. `NOT DISPATCHABLE` / `gated-by:` survive a re-price because they
are not prices.

---

## RESOLVED 2026-08-30 — the owner: **not parked**

> *"ESP is not parked - that was temporary"*

Reading 1, and with a word the ticket did not offer: **temporary**. Neither
"superseded" nor "still in force" is quite what happened — the park was never
meant to outlive the reason for it. That is why the later xtensa ruling reads
as consistent with it (frankB's point stands: *"when we do ESP, do xtensa
first"* really is compatible with *"don't do ESP yet"*), and why nothing in the
tree ever recorded a supersession. There was nothing to supersede. A temporary
call simply expired, and the fossil outlived it.

**Track S is live.** frankS stays staffed, the 23 ranked ESP/xtensa rows stand
at their current prices, and everything the fleet did on ESP on 2026-08-29/30
was correct work, not erosion of a user call. The two new ESP tickets the
coordinator filed at p70/p65 keep their numbers.

### What was struck

The park text was removed everywhere it still read as a standing call:

| file | was |
| --- | --- |
| `done/bug-esp-emit-obj-proc-fixup-non-iram.md` | `prio: 30  # ESP parked (user 2026-07-12): Pascal has prio` |
| `done/bug-esp-idf-heap-linux-mmap-ecall.md` | `prio: 35  # ESP parked …; still the top ESP ticket when resumed` |
| `done/feature-dns-esp-backend.md` | a "The other reason it sits low" section |
| `backlog/feature-dns-esp-wire-nameservers-from-lwip.md` | a Priority paragraph citing the standing call, and its `blocked-by:` on this ticket |

Struck rather than annotated, because the failure mode here was a **reader**
believing a dead ruling, and a fossil with a footnote is still a fossil. The
history is not lost: `ad649f55f` applied the park, `ab584382e` deleted its live
copy, and this ticket records both.

### The general defect is NOT resolved by this answer

frankB's evidence stands on its own merits and outlives the ruling: `ab584382e`
("apply the approved re-triage") rewrote `prio: 30  # ESP parked …` to a bare
`prio: 20` and erased the comment, in the same commit that swept the NilPy hold
from 20 to 55. **One commit, two user rulings, neither mentioned in its
message.** The class has one cause — *a user decision whose only enforcement is
a number, met by a process that rewrites numbers in bulk* — and this answer does
not fix it. It only means the ESP instance cost nothing.

That repair is filed separately as
[[feature-t-a-user-hold-must-survive-a-bulk-re-price]]. It is worth doing even
though both known instances are now closed, because the next hold will be
recorded the same way unless the recording form changes.

### The tell to keep

The park survived in both `done/` tickets, where it could no longer act, and was
deleted from the one live ticket, where it still could — because a re-triage
re-prices open tickets and does not touch `done/`. **Enforcement was destroyed
exactly where it was load-bearing and preserved exactly where it was inert.**
That is the shape to recognise: if a rule appears to survive only in places it
cannot act, it has probably already been erased where it mattered.
