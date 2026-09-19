---
slug: decide-whose-job-is-it-to-notice-a-ticket-has-gone-stale
track: U
prio: 50
type: decide
status: backlog
created: 2026-09-19
found-by: frankS
owner: ""
blocked-by: []
summary: "FIVE stale ticket SUMMARIES were found by hand in one day (2026-09-19) across two lanes, each with a correct body — the part everyone reads contradicting the part nobody scrolls to, and the summary is what carries prio into the ranker, so a stale one promotes dead work to the top of a queue. Before proposing a tool I measured whether detection is possible and IT LARGELY IS NOT, for a reason that kills every future grep proposal: PARTIAL COMPLETION IS THE NORMAL CASE AND IS TEXTUALLY INDISTINGUISHABLE FROM STALENESS — a body-says-done heuristic has recall 1 of 5 on the real cases and flagged 7 of 586 open tickets, ALL SEVEN correctly open with accurate summaries reading "FIXED piece 1 of the three" and "FIXED AT HEAD, STILL WRONG IN THE PIN" (precision 0). The four misses fail for THREE DIFFERENT reasons and only one is textual. The one class that looked mechanically checkable — a summary quoting a compiler diagnostic verbatim — FAILED ITS POSITIVE CONTROL: run against the riscv32 ticket it was designed from it answered not-flagged, because the quoted string is a generic template still in compiler/ with only the one arm fixed. Age is no signal either: nothing open is over 19 days and the top tickets are 0-12 days old, because this tree takes ~250 commits a day — staleness here is VELOCITY, not neglect. THE CHEAP HALF IS BUILT AND DID NOT WAIT FOR THIS TICKET (claim now prints the summary with a last-verified date, `progress.sh verified <slug>` records one, and claim deliberately never stamps it — guarded by a positive control). WHAT IS LEFT FOR THE OWNER IS A COST, NOT A DESIGN: do we want to spend model time, every day, having something read every open ticket against the tree — or is that the job of whoever picks the ticket up? A standing pass over 586 tickets is the only approach measured to work and it is a permanent token commitment, which is his dial. Also measured, independent of the fork: `progress.sh check` already answers the system side partly and emits 45 findings / 36,395 bytes, 20 of them NEAR-DUP — a 36KB report is not read, so a family with precision 0 makes it 36KB plus noise. AND THE TOOL IS ALREADY SPECIFIED AND UNBUILT: `bug-t-check-has-no-aperture-for-a-ticket-whose-body-records-its-own-completion` sits at p60 proposing exactly the body-says-done aperture, filed twenty days ago off a real dispatch loss — the numbers above ARE its measured yield, so it should be read before it is built rather than promoted."
verified: 2026-09-19
---

# The question

**Do we want to spend model time, every day, having something read every open
ticket against the tree — or is that the job of whoever picks the ticket up?**

That is the whole fork and it is answerable in a word. It is stated as a
**recurring cost** and not as "whose job is it", because the cost is the part
that is genuinely the owner's: the token budget is explicitly his dial, and the
only approach measured to work here is a model pass over 586 open tickets on a
cadence. Who-does-what is a design he has no stake in; what it costs, forever,
he owns outright.

**The cheap half needs no answer and is already built** — see *What has already
been done* below. This ticket is only about whether to add the standing spend.

# Why it is worth a decision at all

Five stale summaries in one day, two lanes, **every one with a correct body**.
Three are recorded in CLAUDE.md (`task-b-write-the-lekkerzeilen-pxx-platform-backend`
at **p85 — the highest open number under its umbrella** — saying *"IS A 39-LINE
STUB"* of a file the owner had rewritten to 974 lines; the alt-stack ticket
dispatched at **p70** with forty lines of its own body already saying FIXED;
the DCE ticket still listing arm32/aarch64 as REMAINING after both landed).
Two more were found by this seat the same day.

The cost is not tidiness. **The summary carries the prio into the ranker**, so
a stale one promotes dead work to the top of a queue and a seat is dispatched
to it.

# What I measured before proposing anything

586 open tickets (`backlog-*`, `urgent`, `working`, `unfinished`, `blocked`).

### 1. A text-marker heuristic: recall 1 of 5, precision 0 of 7

The obvious check is "body announces completion while the summary is silent".
Against the five real cases, reconstructed from git at their pre-fix revision:

| ticket | would the rule fire? |
| --- | --- |
| alt-stack | **yes** |
| lekkerzeilen backend | no — body never said FIXED; the *world* changed |
| DCE | no |
| pxxcoswitch/riscv32 | no |
| foreign-thread | no |

On the live backlog the same rule flags **7 of 586**, and inspecting all seven:
every one is a *correctly open* ticket whose summary already says so — "FIXED
**piece 1 of the three**", "RESOLVED **IN TWO HALVES**", "FIXED AT HEAD,
**STILL WRONG IN THE PIN**". **Precision zero.** Partial completion is the
normal case, and it is indistinguishable from staleness by text.

Loosening the markers makes it worse, not better: `no longer` matches 79
tickets and `is fixed` matches 80 — the cry-wolf shape, and a guard that cries
wolf on its first outside run teaches that it can be ignored.

### 2. The four misses fail for three different reasons

- **Body contradicts summary** (alt-stack). Textual. 1 of 5.
- **The summary makes a claim about the CODE that the code now refutes**
  (lekkerzeilen's "39-line stub"; DCE's "arm32/aarch64 remaining"). Nothing in
  the ticket is wrong-looking; the tree moved. Needs execution or judgement.
- **The summary describes a MECHANISM a later change superseded**
  (foreign-thread: `PxxPthreadStart` landed 13 days after the measurement, so
  "a libc pthread" came to name the fixed case). Only re-measuring finds it.

### 3. The one mechanically-checkable class FAILED ITS POSITIVE CONTROL

A summary that quotes a compiler diagnostic verbatim looked checkable: if the
tree no longer contains the string, the ticket quotes something that cannot
happen. 11 open tickets do this. Built it, then ran it against the case it was
designed from — the riscv32 ticket, pre-fix:

    probe = 'target riscv32: unsupported node in IR codegen:'
    flagged = False

**It cannot see its own founding case.** The quoted string is a *generic
template* still in the source; only the `coswitch` arm was added. The check
would have shipped flagging 3 other tickets (unverified) while missing the one
it existed for. A guard that cannot catch the case it was built from is not a
guard, and this one only announced itself because it was given a control.

### 4. Age is not a signal here, and the first attempt to show that was wrong

Top-ranked tickets are **0-12 days old**; nothing open exceeds 19 days. This
tree takes **~250 commits a day** (2,566 in the last ten). Staleness is caused
by **velocity, not neglect** — the lekkerzeilen ticket went stale inside its own
short life — so "flag anything older than N" has nothing to bite on.

*Recorded because it nearly became a number in this ticket:* the first age
measurement used `git log -- <path>`, which **does not follow renames**, and
the per-lane backlog folders are a recent reorganisation. It reported a tidy
"median 13 days, max 19" that was really *days since the file arrived at that
path*. `--follow` gives the real figures above.

### 5. The system-side answer is PARTLY BUILT, and its cost is visible today

`tools/progress.sh check` already carries eleven aperture families, two of them
aimed at this idea from the other side — `STALE-PARK` (prose names a blocker
that has since closed) and `PROSE-EDGE-NOT-IN-FRONTMATTER` (prose states a block
the frontmatter never carried). **Neither reads a summary against its own body**,
and none of the five cases is visible to any of the eleven.

Its present output is **45 findings, 36,395 bytes**, of which 20 are `NEAR-DUP`
and 11 are `STALE-PARK-HELD`. That is the shape a text-marker aperture takes at
scale, and it is the cost this decide has to weigh: a 36KB report is not read,
and adding a family with precision 0 makes it 36KB plus noise.

**AND THE TOOL THIS DECIDE IS ABOUT IS ALREADY SPECIFIED:**
`bug-t-check-has-no-aperture-for-a-ticket-whose-body-records-its-own-completion`
(Track T, **p60**, `low-prio/`), filed 2026-08-30 by frankB off a real dispatch
loss, proposes exactly the missing aperture and states it as the mirror of the
two that exist. Nobody has built it in twenty days.

**The measurements above are that ticket's answer, and it is not the one it
expects.** Its aperture is the body-says-done rule: **recall 1 of 5, precision
0 of 7.** It would have caught its own founding case (`feature-random-library`,
whose log says *"Tier 1 is closed"*) — that is the class it was written from,
and it is one class of three. **It should be read before it is built**, and this
decide is the reason it should not simply be promoted.

# The options

**A — a standing model pass.** Something reads every open ticket against its
own body and against the tree, on a cadence. It is the only approach shown to
be capable of the three classes that matter. **The cost is the decision:** 586
open tickets, re-read periodically, forever. That is a standing token
commitment, and fleet token spend is the owner's dial, not a seat's.

**B — the seat that picks it up.** Already built (below). Costs no compute and
no new judgement: the ticket's summary is put in front of the seat at `claim`,
and `tools/progress.sh verified <slug>` records the outcome.

**C — do nothing, and say so.** Treat a ticket as a claim with a date on it,
and put that sentence in CLAUDE.md. Honest, and it leaves the
p85-pointing-at-finished-work case intact.

# Recommendation: B is done; A is a *later* question, not a foreclosed one

Take no decision on A yet. **B landing is what makes A arguable**, because it
produces the one thing this ticket cannot: a measured failure rate for the
cheap option. If stale summaries keep arriving with `verified:` blank across the
board, that is B not being used and the answer is not more automation. If they
keep arriving with `verified:` dates *on them*, the cheap option has been tried
and failed, and the recurring spend has an evidence base instead of an anecdote.

**Do not read B as this being closed.** And do not build a detector on the
strength of this ticket: the measurements above are the argument against the
cheap ones, and if the answer is A it should be A deliberately, with a budget,
not a greppable subset that flags seven correct tickets and misses four wrong
ones.

# What has already been done (B, landed — this decide did not gate it)

A reversible tooling change in Track T's own lane, so the act-then-report rule
covers it and a filed decide is not a reason to stall the half that needs no
decision:

- **`claim` prints the ticket's own summary**, with `last verified: <date>` or
  `NEVER`, and the two outcomes: `tools/progress.sh verified <slug>` if it still
  reads true, or fix it in the first commit if it does not. A pointer the seat
  has to go and open is the step that does not happen after dispatch.
- **`tools/progress.sh verified <slug>`** stamps `verified: <today>` into the
  frontmatter.
- **`claim` deliberately does NOT stamp the field**, and that is the guarded
  property. A date written by the command that *prompts* the check would record
  "a seat was told to check" while reading as "a seat checked" — certifying the
  very thing the field exists to measure, on every claimed ticket at once.
  `tools/summary_verified_devtest.py` carries that as its positive control;
  injecting the stamp into `claim` reddens four rows, verified by doing it.

# What would change this

A sixth and seventh instance whose *bodies* announce completion while their
summaries stay silent would move recall above 1-in-5 and make the textual check
worth its false positives. Re-run the reconstruction above before assuming it
still holds — and give any detector a positive control drawn from the real
cases, since that is the only thing that caught the diagnostic-quote check.

# Related

- `bug-t-check-has-no-aperture-for-a-ticket-whose-body-records-its-own-completion`
  (T, p60, `low-prio/`) — **the tool this decide is about.** Do not build it on
  its own strength; the numbers above are its measured yield. If the answer here
  is A, that ticket is where A lands and it needs its scope widened past the
  body-says-done class. If the answer is B or C, it should be closed or
  re-scoped rather than left ranked at 60.
- `bug-t-the-watchers-auto-close-copies-a-ticket-into-done-and-leaves-the-original-ranked`
  names a neighbouring hole — two files sharing a slug, rather than one file
  contradicting itself. **They are not one fix** and should not be merged: that
  one is a mechanical bug in the watcher with a mechanical remedy, this one is a
  judgement problem with no measured mechanical remedy.
