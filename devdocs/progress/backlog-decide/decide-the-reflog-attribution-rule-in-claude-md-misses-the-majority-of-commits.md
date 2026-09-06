---
slug: decide-the-reflog-attribution-rule-in-claude-md-misses-the-majority-of-commits
track: U
prio: 55
type: decide
status: backlog
created: 2026-09-06
found-by: frank-coordinator
owner: ""
blocked-by: []
title: "CLAUDE.md's sha-to-checkout rule greps `^<sha> commit` and resolves 43% of commits, not seven in eight — the miss is structured, not occasional"
summary: "CLAUDE.md's attribution method (`git -C ~/<name> reflog --format='%h %gs' | grep '^<sha> commit'`) is CORRECT and its stated RATE is wrong: measured 2026-09-06 over 719 commits and 17 checkouts, `commit` alone resolves 43%, while `commit` plus the `rebase (pick)` family resolves 79% with zero ambiguity. Cause is `tools/sync.sh`, which pulls --rebase before every push: an authoring checkout's own commits are REPLAYED, so the sha that reaches origin/master carries `rebase (pick):` in that checkout's reflog while the `commit:` entry stays on the pre-rebase id. The miss is therefore structured -- highest on the MOST RECENT commit, which is the one anyone is asking about -- and the file's 'the EIGHTH sha not resolving is the instrument telling you it has a failure mode' reads as occasional when it is the majority. DO NOT widen to any `rebase`: `rebase (start)` checks out the UPSTREAM tip and stamps every puller's reflog, which lifts resolution to 53% and makes 289 of 719 shas name TWO seats -- a confident wrong answer wearing the shape of a better one. Text proposed below, NOT edited in; CLAUDE.md is the owner's file. The tooling half is already landed (`732b238d7`, whoholds prints `seat=`)."
---

# The middle row is the finding; the 79% is only the receipt

**Lead with this, because a summary would hide it** (frankD, who found the cause
and then re-ranked my own table):

> **53% resolved with 289 ambiguous is strictly worse than 43% resolved with
> none.** The obvious widening — match any `rebase` — trades *"I don't know"* for
> *"I confidently know, wrongly"*, and a seat name is **addressable**, so the
> wrong answer gets acted on in a way an unresolved sha never does. **The gain is
> entirely in the pick family and it costs nothing.**

`rebase (start)` checks out the UPSTREAM tip, so it stamps every puller's reflog
with whatever sha origin was at. frankD's placement of it: *the same class as this
file's own warning about `git fetch` — an operation that moves refs through every
checkout leaves a trace that looks like authorship.*

# The rule is right, the rate is wrong, and the miss is where it hurts

Nothing here disputes the method. `git log origin/master --grep=<session URL>`
and the reflog are still the two instruments, and the reflog still answers WHERE
a commit was authored rather than WHO authored it.

**What is wrong is the implied hit rate**, and it changes how a reader treats a
miss. The file says *"Verified 2026-09-02: seven of eight shas in one arc, one
checkout, one id"* and *"the EIGHTH sha not resolving is the instrument telling
you it has a failure mode — read that as the tell, not as noise."* A reader takes
that as: resolution is the norm, a miss is the exception worth noticing.

**Measured 2026-09-06 over 719 commits and every checkout under `/home/neo`:**

| rule | resolved | ambiguous |
| --- | --- | --- |
| `commit` only (the file's) | **43%** | 0 |
| `commit` or any `rebase` | 53% | **289** |
| `commit` or `rebase (pick\|reword\|squash\|fixup\|amend\|continue)` | **79%** | 0 |

**The cause is `tools/sync.sh`, which this file mandates.** It pulls `--rebase`
before every push, so an authoring checkout's own commits are replayed: the sha
that lands on origin/master appears in that checkout's reflog under
`rebase (pick):`, and the `commit:` entry stays behind on the pre-rebase id.
Verified on `f00d3d230` (frankD's bracket fix): `rebase (pick)` in frankD's
reflog and in **no other checkout**; `commit:` on its pre-rebase id `f7ee1414a`.
frankD's own statement, which is the sentence worth keeping: **"that is not a gap
in the method, it is the method meeting `tools/sync.sh`."**

DANGLING SHAS BY DESIGN

`f7ee1414a` above is a DOOMED PRE-REBASE ID and is quoted deliberately: it is
the exhibit, not a citation. It is not on origin, and it is not even a valid
object in every checkout — `git cat-file` answers `Not a valid object name` here,
because the id only ever existed in frankD's own store. That is the whole point
the ticket is making, so the marker is added rather than the sha corrected.

Added by frankA 2026-09-06, on the checker's own instruction — its message says
to add this line when a dead sha is quoted on purpose. Worth doing rather than
leaving: a check that fires forever on a ticket that is RIGHT is how a real hit
gets scrolled past, and this one had been the only remaining DANGLING-SHA in the
whole run.

**So the miss is structured, not random**, and it is concentrated exactly where
it costs: a push that had nothing to rebase over keeps its sha and resolves, and
a push that raced anything does not — which is nearly every recent one. The 2026-09-02
arc that verified the rule was an arc whose pushes did not rebase. That is this
file's own *census over the corpus you have* landing on the file itself.

**DO NOT FIX IT BY WIDENING TO `rebase`.** `rebase (start)` checks out the
UPSTREAM tip, stamping every puller's reflog with whatever sha origin was at, so
the wide rule makes 289 of 719 shas name two seats. **A seat name gets believed in
a way a session id does not**, so that middle row is worse than the status quo
while looking like an improvement.

## The exact sentence this retires, quoted so it is not left in beside its own correction

CLAUDE.md today:

> *"Verified 2026-09-02: seven of eight shas in one arc, one checkout, one id. …
> **The EIGHTH sha not resolving is the instrument telling you it has a failure
> mode** — read that as the tell, not as noise."*

**The lesson in that sentence survives and its arithmetic does not.** It frames a
miss as an anecdote with a moral attached; the measurement makes the miss the
majority case, so a reader who meets an unresolved sha and treats it as *the tell*
is reading the common case as the exception. frankD asked for the old line to be
quoted here specifically because **it is the kind of line that gets left in beside
its own correction**, and then both are true-sounding and one is wrong.

## A second, smaller trap in the same command, and it is the better half of the tooling case

The documented command is `git -C ~/<name> reflog --format='%h %gs' | grep
'^<sha> commit'`. **`%h` is the ABBREVIATED sha**, so a full 40-character id
pasted from `git rev-parse` — which is what anyone scripting this produces —
matches nothing, silently, and reads as *"that checkout did not author it"*.

This file's own words for it: **every instrument that lies, lies by being CORRECT
ABOUT SOMETHING ELSE.** The grep is correct about abbreviated shas. Stated in the
ticket rather than only in the tool, at frankD's request, because a reader who
never runs `whoholds` still meets the command here.

## Proposed replacement text, for the owner to edit or discard

Replacing, in "A CLEAN TREE IS NOT EVIDENCE ABOUT A SESSION EITHER", the sentence
beginning *"Plain reflog membership does NOT discriminate"* and the verification
note after it:

> Match on an AUTHORING action, not on presence: `commit`, `commit (amend)`, and
> the `rebase (pick|reword|squash|fixup|amend|continue)` family. **`rebase
> (pick)` is not optional** — `tools/sync.sh` rebases before every push, so an
> authoring checkout's own commits are replayed and the sha that reaches
> origin/master carries `rebase (pick)` while `commit` stays on the pre-rebase
> id. **`rebase (start)` and `rebase (finish)` must be EXCLUDED**: `start` checks
> out the upstream tip and stamps every puller's reflog. Measured 2026-09-06 over
> 719 commits and 17 checkouts: `commit` alone resolves 43%, the authoring-action
> rule resolves 79% with zero ambiguity, and matching any `rebase` resolves 53%
> while making 289 shas name two seats. **An unresolved sha is the common case,
> not the tell** — corroborate with a second sha, and treat two claimants as
> ambiguous rather than as an answer.

Also worth a word: the file's command uses `--format='%h %gs'` and greps
`'^<sha> commit'`, so it matches only an ABBREVIATED sha. A full 40-character sha
pasted from `git rev-parse` silently matches nothing — the same
answers-about-something-else shape, one layer down.

## Done when

The owner has either edited CLAUDE.md or said the rate is not worth the words.
**The tooling half needs nothing from this ticket and is already landed:**
`732b238d7` makes `tools/whoholds.py` resolve and print `seat=<checkout>` under
the authoring-action rule, reporting `ambiguous` when two checkouts claim one sha,
so an agent that uses the tool never types the grep.
