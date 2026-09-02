# `known-incompat/` — not a bug: a known, chosen incompatibility

**The ticket here was RIGHT.** Its measurement is true, reproducible, and worth
having. It is still not a defect, because **both behaviours are correct about
their own implementation** and ours is the one we chose.

That is what separates this folder from `rejected/`, and the separation is the
reason it exists: filing a true measurement under "rejected" misrepresents the
finding, insults the person who measured it, and guarantees a refile the first
time someone else runs the same probe and sees the repo call it wrong.

## The four terminal folders

| folder | what it says |
| --- | --- |
| `rejected/` | the report is **WRONG** — unreachable observable, false premise, not a goal |
| `known-incompat/` | the measurement is **TRUE** and it is **not a defect** — chosen, not tolerated |
| `low-prio/` | real, probably correct, **not worth ranker attention** — no plan, no claim it is wrong |
| `rainy-day/` | real, intended, **deferred** — a future plan |

## What qualifies

All three must hold:

1. **The measurement reproduces.** A divergence nobody can demonstrate is not a
   divergence, it is a rumour.
2. **No program observes a wrong VALUE.** Store the result in its declared type
   and compare that — the test in CLAUDE.md's goal section. If a correct program
   gets a wrong answer, it is a bug and belongs in a backlog.
3. **Neither implementation is wrong.** Two valid representational or
   evaluation choices, each reported faithfully by its own compiler.

If the third fails — if we are simply wrong and have decided not to fix it — that
is `low-prio/`, not this. **This folder is not a place to park defects.**

## Write it as CHOSEN, never as tolerated

Wording carries weight here. *"We accept this divergence"* concedes something was
off and invites the next reader to re-open it. *"Both answers are correct about
different representations"* closes it. Say which behaviour we chose and why the
other is equally valid.

**A truthful instrument returning an answer you did not expect is not a defect.**
`SizeOf(a+b)` answering 8 is a correct statement about a pxx expression, exactly
as FPC's 4 is correct about an FPC one — and the operator exists precisely so a
programmer need not assume. The repo's general rule is that an instrument which
lies, lies by being correct about something else; this is the mirror case, where
it is not lying at all and the expectation was the wrong part.

## Every entry owes the reader three things

- **The measurement**, with the compiler sha256 and commit it was taken at.
- **Which behaviour we chose, and the reason** — architecture, precision, cost.
- **What would REOPEN it**: real source, not a probe, that is correct elsewhere
  and wrong here *because of* the divergence. Naming this is what stops the
  argument being re-run from scratch.

## These are user-facing

A divergence a programmer can hit belongs in the language's own divergences
document as well as here — `devdocs/dev/nilpy-semantics-divergences.md` is the
pattern for Nil-Python. This folder is the evidence; that document is where
someone writing code will actually look.
