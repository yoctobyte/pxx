---
track: U
prio: 30
type: decision
blocked-by: []
summary: "devdocs/dev/ (50 files) and devdocs/developer/ (58 files) both hold internal developer docs. A grep in the wrong one returns silence, which reads like a refuted citation rather than a mislocated file. Decide whether to consolidate, and if so which name wins, given 631 citations point at dev/ and 40 at developer/."
status: backlog
owner: unassigned
---

# Two `devdocs` developer directories, and the failure mode is a false refutation

- **Track U** — a decision, not work: the fork is which name wins and whether the
  churn is worth it, and neither is settleable from the code.
- Filed 2026-08-28 by frankB after the hazard fired: a citation to
  `devdocs/developer/plan-networking.md:117` was checked against `devdocs/dev/`,
  returned nothing, and was one step from being recorded as a false citation.

## Measured

| directory | `.md` files | citations to it across the repo |
| --- | --- | --- |
| `devdocs/dev/` | 50 | **631** |
| `devdocs/developer/` | 58 | **40** |

So neither is vestigial — `developer/` holds *more* files while receiving 6% of
the references. `plan-networking.md`, `architecture.md`, `c-interop.md`,
`allocator-platform-design.md` and `acronyms.md` all live in the low-traffic one.

## Why this is worth a decision rather than tolerating

The failure mode is not "a reader is briefly confused". It is that **a search in
the wrong directory returns silence, and silence is indistinguishable from
refutation.** Someone verifying a citation greps, finds nothing, and concludes
the citation is wrong — the file is right there under the other name.

That is a sharper version of a hazard this repo has already named: a confirming
or empty measurement of the wrong configuration ends an investigation, because
nothing about it prompts a second look. Here the wrong configuration is a
directory name that differs by four characters.

CLAUDE.md itself cites both spellings in different places, which is how the
convention stays alive on both sides.

## Options

1. **Consolidate into `devdocs/dev/`** — matches 94% of existing citations, so
   the smaller move. Costs: 58 files change path, ~40 citations need rewriting,
   and `git log --follow` is needed to trace them afterwards.
2. **Consolidate into `devdocs/developer/`** — the more descriptive name and the
   larger file count, but rewrites 631 citations. Almost certainly not worth it.
3. **Leave both, document the split** — a line in CLAUDE.md and both READMEs
   saying which topics live where. Zero churn, and the hazard survives in
   reduced form: a reader who knows the split still greps the wrong one first.
4. **Leave both, add a redirect stub per file** — highest file count, lowest
   value; noted only so the option set is complete.

## Recommendation

**Option 1**, with two conditions that are the actual reason this is a decision
rather than a chore:

- **Do not rewrite session records to match.** Handoffs, resolved tickets and
  `done/` write-ups are historical records of what a past session actually ran;
  CLAUDE.md is explicit that rewriting them falsifies history. Their stale paths
  should stay stale. That means option 1 does not fully eliminate the hazard, it
  reduces it to the archive — which is the honest outcome and should be stated
  up front rather than discovered later.
- **A move this wide should not be interleaved with a pin**, since it touches
  no code but a great many paths that tooling and hooks may match on.

If the churn is judged not worth it, **option 3 is a legitimate answer** and
better than an option-1 attempt that stalls half-done — 58 files split across
two directories under one name would be strictly worse than today.

## Not in scope

Anything under `devdocs/progress/**` (the board) or `docs/**` (Track D's
public docs). This is only the two internal developer-doc directories.

## Second instance, in a different tree — the progress board, 2026-08-28

The coordinator concluded a ticket had not been filed, on the strength of **two greps
with different wording plus an mtime sweep**, and filed a duplicate. Track O had
already filed it. The searches covered `devdocs/progress/backlog/` and
`devdocs/progress/unfinished/`; the ticket was in **`devdocs/progress/backlog_new/`**
— a fourth directory that `ready`/`next` *do* scan and the searches did not.

**This is the same failure as the `devdocs/dev` vs `devdocs/developer` case this
ticket was filed about, in a different tree.** Which matters, because it means the
subject is not "someone should merge two doc directories" but a general property:

> **A search across a set of sibling directories is only as complete as the list of
> siblings the searcher happened to type.** Nothing in the empty result names the
> directories it did not visit, so a blind search and a true absence are the same
> output.

Both instances were *non-existence* claims, which is the direction that does not
survive a single search. The cost here was small — one duplicate ticket, folded back
in the same hour — but the mechanism is identical to the one that nearly recorded a
correct citation as false earlier the same day.

**Worth noting for whoever decides this:** the fix that would have caught it is not a
tidier directory layout, it is `tools/progress.sh` itself — a ticket search that knows
its own set of status directories cannot omit one. A tool that enumerates the
canonical list is a construction that cannot express the mistake; remembering to type
four paths is a documented trap.
