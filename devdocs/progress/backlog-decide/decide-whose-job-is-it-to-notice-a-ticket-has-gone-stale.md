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
summary: "FIVE stale ticket SUMMARIES were found by hand in one day (2026-09-19) across two lanes, each with a correct body — the part everyone reads contradicting the part nobody scrolls to, and the summary is what carries prio into the ranker, so a stale one promotes dead work to the top of a queue. Before proposing a tool I measured whether detection is possible, and IT LARGELY IS NOT: a text-marker heuristic has recall 1 of 5 on the real cases and flagged 7 of 586 open tickets, ALL SEVEN correctly-open with accurate summaries (precision 0). The four misses fail for THREE DIFFERENT reasons and only one is textual. The one class that looked mechanically checkable — a summary quoting a compiler diagnostic verbatim — FAILED ITS POSITIVE CONTROL: the riscv32 ticket's quoted string is a generic template still in the source, because only the specific arm was fixed. Age is no signal either: nothing open is over 19 days and the top tickets are 0-12 days old, because this tree takes ~250 commits a day — staleness here is caused by VELOCITY, not neglect. So the fork is not technical and no tool should be built until it is answered: WHEN A SEAT IS HANDED A TICKET, WHOSE JOB IS IT TO NOTICE THE TICKET IS OUT OF DATE — THE SYSTEM'S, OR THE SEAT'S? AND THE TOOL IS ALREADY SPECIFIED AND UNBUILT: `bug-t-check-has-no-aperture-for-a-ticket-whose-body-records-its-own-completion` sits at p60 proposing exactly the body-says-done aperture, filed twenty days ago off a real dispatch loss — the numbers above ARE its measured yield, and they say it would catch its own founding case and one class of three, so it should be read before it is built rather than promoted. Recommendation inside: the seat's, made cheap and recorded, because every undetectable class requires reading the ticket against the tree, which is what a seat about to work on it does anyway."
---

# The question

**When a seat is handed a ticket, whose job is it to notice the ticket is out
of date — the system's, or the seat's?**

No implementation noun in it, and that is deliberate: answer this and the
engineering follows; build first and we get a checker for the one class that
happens to be greppable.

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

**A — the system's.** Detect staleness. Measured above: the cheap forms do not
work. In practice this means an **LLM pass over 586 open tickets**, re-run
periodically, reading each body against its summary and against the tree. It is
the only approach shown to be capable of the classes that matter. It has a real
recurring cost and needs an owner.

**B — the seat's, made cheap and recorded.** Every undetectable class requires
reading the ticket against the tree — which is exactly what a seat about to
work on it does anyway. The failure is not that nobody notices; it is that the
noticing happens **after dispatch** and nothing records it. So: `claim` prints
"re-verify the summary before starting; if it is wrong, fix it in your first
commit", and a `verified:` date in the frontmatter that `claim` and `resolve`
update. Costs no compute and no new judgement.

**C — do nothing, and say so.** Treat a ticket as a claim with a date on it,
and put that sentence in CLAUDE.md. Honest, and it leaves the p85-pointing-at-
finished-work case intact.

# Recommendation: B, and not a tool until B has been tried

B addresses all three classes because it puts the check where the knowledge
already is. A is the only thing measured to *work*, but it pays a recurring
cost to find something a seat is about to discover anyway — and the five found
today were all found by seats reading, which is B happening informally and
going unrecorded.

**Do not build a detector on the strength of this ticket.** The measurements
above are the argument against the cheap ones; if the answer is A, it should be
A deliberately, with an owner and a budget, not a greppable subset that flags
seven correct tickets and misses four wrong ones.

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
