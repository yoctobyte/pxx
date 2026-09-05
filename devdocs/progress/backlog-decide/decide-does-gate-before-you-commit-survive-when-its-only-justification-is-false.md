---
track: U
prio: 40
type: decide
status: backlog
blocked-by: []
found: 2026-09-05
found-by: frankS (measured), frank-coordinator (source-confirmed and filed)
summary: "CLAUDE.md's `GATE BEFORE YOU COMMIT, NOT AFTER` rests entirely on the claim that quick's FPC seed canary only fires on an uncommitted tree. `tools/gate.sh` arms it against the MERGE-BASE, so a committed-but-unpushed tree — and a tree whose `compiler/` has moved since the last green seed — still gets full FPC coverage. The false sentence is being corrected separately; this ticket is only the question of whether the INSTRUCTION should survive its justification. NOT a near-miss: it is a false CONSTRAINT, not a false safety."
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

**Two sources, failing differently.** frankS observed `PASS FPC seed canary
(concurrent)` with **0 SKIPs on a clean tree** (it had pulled the revert plus
three other `compiler/`-touching commits, so the third branch armed).
frank-coordinator then read the source. Neither settles it alone.

## THIS IS A FALSE CONSTRAINT, NOT A FALSE SAFETY

**Nothing has been under-gated.** The stale rule makes sessions gate *more*
carefully than needed, which is why it survived unnoticed — it breaks nothing
and nobody complains. Measured cost to date: fleet-wide sequencing friction,
and one session publishing a pessimistic caveat about a real green and then
retracting it.

**Do not rank this as a near-miss.** No defect reached anyone through it.

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
