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
