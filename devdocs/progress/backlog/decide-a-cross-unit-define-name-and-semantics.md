---
track: U
prio: 40
type: decide
blocked-by: []
summary: "A define that crosses unit boundaries is order-dependent BY CONSTRUCTION — `{$DEFINEGLOBAL}` reads as 'global' while the mechanism is claim-and-skip. Four questions (name, undefinability, scope, visibility to earlier units) must be settled before anyone builds it, and nothing currently pulls on the feature: its motivating case was closed as synthetic."
---

# What a cross-unit define is called, and what it means

**Split out of [[feature-p-defineglobal-a-define-that-crosses-unit-boundaries]] 2026-08-19,
on frank2's triage recommendation.** That ticket is genuine work, but it is **blocked on
judgement, not on engineering** — it carries four design questions and no way for an engineer
to settle them. Left as a `feature` it reads as buildable and gets picked up by someone who
then has to guess.

**Nothing is waiting on this.** Its motivating case was closed as synthetic, so there is no
deadline; the cost of leaving it open is zero and the cost of guessing is a dialect feature
we cannot rename later.

## The fork, in one line

**The honest name is the decision.** The mechanism is *first-one-wins claim-and-skip*, which
is **order-dependent by construction** — the exact property that
[[bug-p-uses-order-does-not-decide-which-unit-wins]] worked to eliminate. That is fine *when
a program deliberately asks for it* and a bug *when it happens by accident*, so the spelling
has to make the dependence obvious at the use site.

`{$DEFINEGLOBAL}` reads as "global" — i.e. as a property of the program — when it actually
means "whoever gets here first claims it". The ticket itself floats **`{$CLAIM}`** as more
honest. That is the question worth the user's attention; the other three follow from it.

## The four questions, verbatim from the feature ticket

1. **Ordering.** "First one wins" makes the answer depend on `uses` order. Acceptable when
   the program asked for claim-and-skip, unacceptable as an accident — so the name and docs
   must make the dependence obvious.
2. **Can it be undefined?** A global `{$UNDEF}` reopens the same race. *Ticket's lean:*
   set-once, never cleared, which is also the cheapest to implement.
3. **Scope of "global".** Whole compilation, presumably — rather than "all units compiled
   after this point in the uses graph", which is subtler and harder to reason about.
4. **Visibility to units compiled EARLIER.** Does it survive into a used unit's own
   conditionals if that unit is re-entered? *Ticket's lean:* almost certainly no — and
   saying so is cheaper than discovering it.

## Recommendation

**Answer question 1 (the name) and questions 2-4 fall out with the leans already recorded.**
If the name says claim-and-skip, then set-once follows (a claim you can release is not a
claim), whole-compilation scope follows, and no-retroactive-visibility follows.

**Adjacent work, worth reading first:** frank3's import/uses refactor landed 2026-08-19 and
settled how a NilPy import names another language, including the quoted-path spelling and
the `as` alias. That is neighbouring territory for how a program *names* and *claims* things
across unit boundaries, and it may make one spelling read as more natural than the other.

## What happens after

Once decided, **re-file the work into the owning lane (Track P)** and drop this ticket into
`decided/`. A decided ticket that is never re-filed is invisible to `ready`/`next` and gets
rediscovered — sometimes with a fix the decision already rejected.

## Log
- 2026-08-19 — split from the feature ticket during the A/P/C feature triage.
