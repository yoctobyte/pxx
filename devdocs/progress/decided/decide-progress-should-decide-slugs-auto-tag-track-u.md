---
prio: 30
track: U
blocked-by: []
---

# Should `decide-*` slugs auto-tag Track U in the ranker?

- **Type:** decide (Track U — a convention call, not code)
- **Status:** backlog — filed 2026-08-08 while wiring the W/M letters
- **Owner:** —

## The fork

CLAUDE.md says plainly: *"The `decide-*` tickets already in the backlog ARE
Track U."* The ranker does not know that. `decide-*` tickets that carry
`track: U` in frontmatter resolve to U; the ones that don't fall through to the
prose/slug heuristics and land wherever those point — e.g.
`decide-nilpy-parallel-capture-semantics` currently resolves to **A**.

So today the escalation lane is split: some open questions sit in U, others are
mixed into A's ready queue, where an agent may pick one up and *guess* — which
is the exact failure Track U exists to prevent.

## Options

1. **Auto-tag `decide-*` -> U in `Ticket.track`** (a 3-line rule beside the
   S/O/E arms, with the same explicit-declaration tie-break the M rule needed).
   Matches the documented rule; instantly correct for every future `decide-`.
   Cost: it moves an unknown number of tickets out of A's/N's ready queue in one
   step, changing what `next` hands out.
2. **Backfill `track: U` frontmatter** on the existing `decide-*` tickets and
   leave the tool alone. Explicit, auditable, no behaviour change for anything
   else — but the next hand-written `decide-` without frontmatter re-opens the
   gap.
3. **Both** — the rule for correctness, the backfill so the files agree with it.
4. **Neither** — accept that a `decide-` in another lane's queue is fine because
   the agent that hits it will recognise the slug.

## Recommendation

**Option 3.** The rule is what makes it durable and the documented convention
already asserts it; the backfill just makes the files honest. Option 4 relies on
an agent noticing a naming convention mid-queue, which is precisely the kind of
"it'll be obvious" assumption the W/M collision showed does not hold.

Deliberately NOT done unilaterally: it changes which tickets `next` hands out
across several lanes, and that is a steering decision, not a bug fix.

## Related
[[meta-track-w-collision-windows-vs-website]],
[[chore-progress-flag-prose-only-track-decl]]

## 2026-08-10 — half done: the backfill is complete (it was ONE file)

**Measured before acting**, and it dissolves this ticket's blocking concern. The
worry was that auto-tagging *"moves an unknown number of tickets out of A's/N's
ready queue in one step, changing what `next` hands out"* — a steering decision.

That number is **one**. Every other live `decide-*` already declared
`track: U`. The single offender was
[[decide-nilpy-parallel-capture-semantics]], which declared Track U **in its
prose** — *"a semantics fork only the user settles"* — while carrying no
`track:` frontmatter, so the ranker put it in **Track A's queue at prio 5**.

That is the exact failure [[meta-track-w-collision-windows-vs-website]] taught:
declare the track in FRONTMATTER, because that is what the ranker reads.

**Done (user, "fix that ticket"):** `track: U` added. Verified it left Track A's
ready queue and appears in U's.

## What remains: the RULE

Option 1 of the fork — auto-tag `decide-*` -> U in `Ticket.track`, ~3 lines
beside the S/O/E arms, with the same explicit-declaration tie-break the M rule
needed. The backfill fixes today; the rule is what stops the next hand-written
`decide-` without frontmatter from re-opening the gap.

Not done here because it is `tools/progress.py` — **Track T's file** — and worth
doing deliberately rather than tacked onto a docs commit. The steering risk that
made the whole ticket a Track U question is now gone (the backfill already moved
the only affected ticket), so what is left is ordinary Track T work, not a
decision.

Suggested re-file: `chore-t-auto-tag-decide-slugs-track-u`.

## CLOSED 2026-08-11 (user) — STALE, no rule needed

> "there was one ticket without the proper tagging, that ticket was edited, the
> question is stale." — user

The fork was posed as a steering question because option 1 (the ranker rule)
*"moves an unknown number of tickets out of A's/N's ready queue in one step"*.
That number was measured and it was **one** —
[[decide-nilpy-parallel-capture-semantics]], which declared Track U in prose but
carried no `track:` frontmatter. It was edited. There is nothing left to steer.

**Re-measured at close**, because "one file" was the claim the whole closure
rests on. Every `decide-*` ticket lacking `track:` frontmatter is in `decided/`
— nine of them, all closed, none ranked by `next`/`ready`, so none can be handed
to an agent to guess at. **Every live `decide-*` declares `track: U`.**

## The rule is deliberately NOT built

Option 1 was kept alive in the 2026-08-10 log as "what remains", with a
suggested re-file to Track T. Declined: it is a ~3-line rule in
`tools/progress.py` guarding against a hand-written `decide-` that omits
frontmatter, and CLAUDE.md already tells every agent to declare the track in
frontmatter *because that is what the ranker reads*
([[meta-track-w-collision-windows-vs-website]]). If the gap ever re-opens it
costs one line of frontmatter to close again — the same edit that closed it this
time. Not worth a tool change carrying its own regression surface.

Re-open only if an untagged `decide-` actually reaches a lane's ready queue
again. One occurrence is not a pattern.

## POSTSCRIPT 2026-08-11 — the same failure, a different slug family

Within the hour of closing this, [[feature-nilpy-parallel-for-in]] was found
resolving to **Track A**: its body says *"Track N — Nil-Python frontend"* in
prose, its frontmatter said nothing, so the ranker guessed — and guessed the
shared-core lane, where the sole-A guard applies.

Not a contradiction of the closure above (that was scoped to `decide-*` slugs,
and every live one of those is tagged), but the same root cause one family over:
**prose-declared track, absent frontmatter.** Fixed by adding `track: N`.

So the rule declined here would not have caught it either — an auto-tag on
`decide-*` says nothing about `feature-*`. If this recurs a third time the useful
fix is not per-slug rules but a `check` warning for any ticket whose prose names
a track its frontmatter does not declare. Related:
[[chore-progress-flag-prose-only-track-decl]], which is exactly that.
