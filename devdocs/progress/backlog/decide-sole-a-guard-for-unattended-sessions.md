---
prio: 55
track: U
type: decide
blocked-by: []
---

# How should an UNATTENDED session satisfy the sole-A guard?

- **Type:** decide (Track U — a coordination policy call, not code)
- **Raised:** 2026-08-09 by an overnight autonomous session that hit this four
  times in one night.
- **Owner:** user

## The fork

CLAUDE.md's cold-start rule says: before taking a Track A ticket — or a Track P
edit touching the shared `lexer.inc`/`parser.inc` — *"confirm you are the only
agent on Track A right now; ask the user if you can't tell."* An unattended
session **cannot ask**, so the documented fallback is to skip and take a
non-shared ticket.

That fallback works, and it is what this session did. But over one night it
parked four items whose fix sites are one condition each, all in
`compiler/parser.inc`:

| ticket | prio | the fix |
| --- | --- | --- |
| [[bug-nilpy-calling-an-instance-named-like-its-class-runs-the-constructor]] | 55 | one guard on an `if` at ~9060 |
| [[bug-nilpy-subscript-read-without-getitem-yields-garbage]] | 35 | widen a gate, add a raise |
| [[bug-nilpy-augmented-subscript-evaluates-its-index-twice]] | 30 | two desugars, ~30 lines apart |
| [[bug-nilpy-list-sort-method-missing]] | 50 | the container method-call site |

Two of those are **silent wrong values** in ordinary code (`parser = Parser(1)`
then `parser(2)` returns a pointer). They are not parked because they are hard;
they are parked because nobody was awake.

## Options

1. **Keep the rule as-is.** Safe, and the cost is visible: shared-file bugs wait
   for an attended session. Fine if attended sessions are frequent.
2. **A standing grant in the session prompt.** The user writes "you are sole-A
   tonight" when launching an unattended run, exactly as this session was told
   "the user confirmed sole-A in the previous session". Cheapest, and it puts
   the decision where the user already knows the answer — they know who else is
   running.
3. **A lock file the agents take.** `devdocs/progress/tstate/` or a
   `working/.lock-A` that `progress.sh claim` writes and checks, so "am I sole-A"
   becomes a question an agent can ANSWER rather than one it must ask. Real work,
   but it removes the human from the loop permanently.
4. **Narrow the guard to what it protects.** The rule exists so two agents do
   not edit the same shared file concurrently. A single-line edit in
   `parser.inc` guarded by a fresh `git pull --rebase` + the self-host gate is
   arguably already safe; the hazard is a long-running divergent edit, not any
   edit at all.

## Recommendation

**Option 2 now, option 3 if unattended runs become routine.** The grant costs
one sentence and unblocks the whole class; the lock file is the durable answer
but should not gate tonight's backlog.

Option 4 is tempting and I do not recommend deciding it casually — the rule's
value is that it needs no judgement in the moment, and "it was only one line"
is exactly how a shared-file collision gets rationalised.

## What this session did meanwhile
Skipped all four, took non-shared work, and left each ticket with the fix site
located to the line so an attended session can land them quickly. Nothing is
lost but latency.

## 2026-08-09 — the blocked list is now SIX, and two of them crash

Adding evidence rather than re-arguing the fork. Tickets that are diagnosed to
the line and cannot be written from an unattended Track N session because the
fix is in `parser.inc`:

| ticket | prio | symptom |
| --- | --- | --- |
| `bug-nilpy-subscript-of-a-call-result-ignores-the-index` | 60 | `f()[1]` on a str yields char 0; `f()[0][0]` drops the second index; `g()["k"]["j"]` **SEGFAULTS** |
| `bug-nilpy-a-class-used-as-a-value-segfaults-or-refuses` | 60 | `for cls in [A]: cls(3)` **SEGFAULTS** |
| `bug-nilpy-calling-an-instance-named-like-its-class-runs-the-constructor` | 55 | wrong object |
| `bug-nilpy-list-sort-method-missing` | 50 | missing method |
| `bug-nilpy-subscript-read-without-getitem-yields-garbage` | 35 | garbage value |
| `bug-nilpy-augmented-subscript-evaluates-its-index-twice` | 30 | double side effect |

What changed since this was filed: the top two are now the highest-priority open
NilPy bugs, they are both **silent-then-crashing** rather than merely wrong, and
both were found by compiling ORDINARY programs (a CSV parser; a class registry)
rather than by probing. The queue's own `next --track N` offered one of them as
the top item and had to be marked `blocked-by` this decision to stop it
resurfacing.

None of this argues for a particular answer — a wrong call about concurrent
Track A edits is worse than a delay. It is here so the cost of the current
default is visible when the fork is settled.

## USER STANCE 2026-08-10

> "unattended sessions - this will screw up sooner or later. all issues so far
> were easily recovered [...] track T is up and running, should save us time.
> and i no longer believe in unattended." — user

That answers the fork: **option 2 (a standing grant in the launch prompt)**, and
**option 3 (a lock file) is rejected** — it is infrastructure for a mode that is
not going to be run. The user knows who else is running at launch time; that is
one sentence, not a subsystem.

### The ticket's own evidence has since evaporated

It argued from four bugs parked in one night for want of permission. Re-checked
2026-08-10: **three are `done/`**, fixed in ordinary attended sessions —
`bug-nilpy-calling-an-instance-named-like-its-class-runs-the-constructor`,
`bug-nilpy-subscript-read-without-getitem-yields-garbage`,
`bug-nilpy-augmented-subscript-evaluates-its-index-twice`. The fourth,
`bug-nilpy-list-sort-method-missing`, is largely fixed too (bare `.sort()` and
`reverse=` work; only `key=` remains) and has been re-measured and dropped to
prio 35.

So the cost the ticket was built on — shared-file bugs waiting indefinitely —
did not materialise. Attended sessions cleared them within a day. That is the
strongest argument for doing nothing beyond the standing grant.

**Pending only the user's confirmation to resolve as option 2.**
