---
track: U
prio: 40
type: decide
status: backlog
blocked-by: []
found: 2026-09-05
found-by: frankS (measured), frank-coordinator (source-confirmed and filed)
summary: "CLAUDE.md's `GATE BEFORE YOU COMMIT, NOT AFTER` rests entirely on the claim that quick's FPC seed canary only fires on an uncommitted tree. `tools/gate.sh` arms it against the MERGE-BASE, so a committed-but-unpushed tree — and a tree whose `compiler/` has moved since the last green seed — still gets full FPC coverage. The false sentence is being corrected separately; this ticket is only the question of whether the INSTRUCTION should survive its justification. Rank on the MEASURED friction (over-gating, observed), but the hazard is two-directional: the same false belief read the other way is a live under-gating mechanism, unobserved and — because nothing durable records working-tree state at gate time — unobservable after the fact."
---

# Does "gate before you commit" survive when its only justification is false?

> **This is a decision about an INSTRUCTION, not about the sentence.** The
> factually wrong sentence in CLAUDE.md is being corrected as an ordinary fix
> (routed to frankB, both sources in the commit). That correction is not blocked
> on this ticket and this ticket must not delay it.

## The fork

CLAUDE.md carries two things in one paragraph:

1. **A claim:** *"`gate.sh quick`'s FPC seed canary only runs while `compiler/**`
   has UNCOMMITTED changes; on a clean tree it prints `SKIP` and you get no FPC
   coverage at all."* — **FALSE against the code.**
2. **An instruction derived from it:** *"GATE BEFORE YOU COMMIT, NOT AFTER."*

Correcting (1) leaves (2) standing with nothing under it. **That is the fork.**

## What the code actually does

`tools/gate.sh` arms the canary against the **merge-base**, not HEAD:

```
seed_base=$(git merge-base origin/master HEAD)
if   ! git diff --quiet "$seed_base" -- compiler/          # committed-but-unpushed ARMS it
elif [ -z "$seed_green" ] || ! git cat-file -e ...         # no recorded green seed ARMS it
elif ! git diff --quiet "$seed_green" HEAD -- compiler/    # compiler/ moved since ARMS it
```

Its own comment: *"ARMED AGAINST THE MERGE-BASE, not against HEAD."* An adjacent
check names the divergence as deliberate: *"CLAUDE.md's rule that quick's canary
only fires on an UNCOMMITTED tree is a footgun worth not copying."*

**Three independent observations, and the first two are predictions that
FAILED.** frankS and frankA each predicted a SKIP on a clean tree and each
reported the prediction failing rather than quietly dropping the caveat — which
is the only reason this surfaced at all.

**AND ONE TESTED ON PURPOSE, which is a cleaner citation than any of the three
predictions.** frankA, 2026-09-05 at tip `7fda453d4`: a gate run on a **CLEAN
tree** — everything committed and pushed, `git status --porcelain` empty at the
moment of the run — with `FPC seed canary (concurrent)` **ARMED and PASSED**.
The three earlier instances were all sessions *predicting* a SKIP and being
surprised by a PASS; this one is the same claim tested deliberately, under known
and stated conditions. **If this ticket needs a single citation for "the rule is
false", use this one** — a surprise is evidence, a designed test is proof.

**Two sources, failing differently.** frankS observed `PASS FPC seed canary
(concurrent)` with **0 SKIPs on a clean tree** (it had pulled the revert plus
three other `compiler/`-touching commits, so the third branch armed).
frank-coordinator then read the source. Neither settles it alone.

## THE MEASURED HARM IS OVER-GATING; THE UNMEASURED ARM POINTS THE OTHER WAY

**Everything observed is over-gating.** The stale rule makes sessions gate
*more* carefully than needed, which is why it survived unnoticed — it breaks
nothing and nobody complains. Measured cost to date: fleet-wide sequencing
friction, and one session publishing a pessimistic caveat about a real green
and then retracting it.

**Rank on that friction.** No defect has been shown to reach anyone through it.
But see the next section before recording the hazard as one-sided: *no lane has
been measured to under-gate* and *no lane could be*, and those are different
sentences.

**But the harm is not strictly one-directional, and frankA named the arm this
ticket first missed.** Two sessions (frankS, frankA) independently predicted
their clean-tree gate would SKIP the canary and hedged their own greens as
narrower than they were — **the optimistic direction, and harmless.** The same
belief read the other way is not: *a session that believes the canary is dead on
a clean tree may gate after committing and think it got no FPC coverage when it
did — or skip a gate it has concluded is worthless.* That is a live mechanism
for under-gating, and it is why "correct the sentence" is not optional even if
the instruction survives.

**No instance of that arm has been observed — and it is UNOBSERVABLE BY
CONSTRUCTION, which is the part that should decide how this is read.** An
earlier revision of this ticket said both sessions *checked* their compiler
commits had `compiler/**` genuinely uncommitted. **That check never happened and
could not have** (frankA, correcting its own sentence, which this seat had
quoted as measured because it arrived beside things that were): nothing durable
captures working-tree state at gate time, and because the canary arms off the
merge-base, **a gate run before a commit and a gate run after it emit the
identical `PASS` line.** The very property that makes CLAUDE.md's sentence false
is what destroys the evidence that would settle whether anyone acted on it.

So the honest form is *neither session has any reason to believe it under-gated,
and neither can demonstrate it* — not *both checked*. That is still a fine
reason to rank on the friction. It is not a reason to record a check that cannot
exist, and an absence of instances is here **weak evidence**, not strong: this
detector has zero reach into its own question.

## Options

- **A — Delete the instruction.** Its justification is gone; the canary covers
  the committed-but-unpushed case. Lanes gate when convenient.
- **B — Keep it, on a NEW justification** if one exists that was never written
  down (e.g. an unrelated reason committing first is worse). **Requires someone
  to state that reason** — keeping an instruction whose stated basis is false,
  without supplying a new one, is how the next stale rule is made.
- **C — Keep it as a weak preference**, explicitly marked as convention rather
  than mechanism.

## Recommendation (frank-coordinator)

**A**, unless someone can supply B's missing reason. The rule's whole force came
from "you get no FPC coverage at all", which is untrue. A surviving instruction
with a deleted rationale is exactly the *stale imperative obeyed by tooling
while false in the world* that CLAUDE.md warns about — and CLAUDE.md is the one
file every session loads at startup and cannot re-derive, so its authority
converts an out-of-date sentence into fleet behaviour.

**Not decided here.** Option A changes what every lane does, which makes it the
owner's, not this seat's.
