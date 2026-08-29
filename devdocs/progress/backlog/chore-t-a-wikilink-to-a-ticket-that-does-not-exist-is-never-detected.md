---
track: T
prio: 30
type: chore
blocked-by: []
summary: "52 distinct ticket-convention [[wikilinks]] across devdocs/progress resolve to no ticket (71 references; 13 cited by live, non-done tickets). Some are renames leaving a dead trail; some appear never to have been filed, which is work hidden behind a link that looks like a citation. Nothing checks."
status: backlog
owner: unassigned
---

# A `[[wikilink]]` to a ticket that does not exist is never detected

- **Type:** chore -- Track T (board tooling, sibling of
  [[chore-t-nothing-re-checks-a-blocked-by-edge-after-its-blocker-closes]]).
- Filed 2026-08-28 by frankB, found while checking whether a p65 ticket's
  reference to `feature-nilpy-corpus-html5lib` pointed at anything. It does not.

## Measured

Restricted to links matching this repo's ticket slug conventions (`bug-`,
`feature-`, `decide-`, `chore-`, `meta-`, `regression-`, `compat-`, `idea-`,
`tstate-`), so memory-namespace links (`project_*`, `feedback_*`), devdocs
filenames and session notes are excluded:

| | |
| --- | --- |
| distinct targets resolving to no ticket | **52** |
| total references | **71** |
| of those, cited by a **live** (non-`done`) ticket | **13** |

The first count I took was **252**, because I matched "not a ticket slug"
rather than "a link that was meant to be a ticket" -- `[[...]]` here spans
several namespaces. The narrowing is recorded because a sweep built on the wide
number would have been mostly noise, and the wide number looked more alarming.

## Two different defects wearing one shape

The second is why this is worth doing.

- **Rename** -- the ticket exists under a different slug. Costs a dead trail:
  someone verifying a claim follows the link, finds nothing, and cannot tell
  whether the reference is stale or the claim is false. Spot-checked:
  `bug-c-bitfield-packing-sizeof-vs-gcc` (a bitfield cluster exists under other
  names), `bug-p-assert-does-not-raise-eassertionfailed` (now
  `compat-pascal-assert-halts-instead-of-raising-eassertionfailed`, which also
  changed type and track).
- **Never filed** -- the link is a promise, not a citation. Spot-checked:
  `feature-nilpy-future-import-noop` and `compat-pascal-subrange-storage-size`
  match nothing under any name. Same shape as an unexecuted
  `(to file / relay to ...)` row: work recorded as though it has a home, which
  does not.

**Not exhaustively classified.** I spot-checked five of the thirteen live ones.
Which bucket each falls into is the sweep's job, and the distinction matters
because a rename wants a link fixed while a never-filed wants a ticket written.

## Why it is not detected today

`tools/progress.sh check` validates board state -- `working/` locks, stale
boards, dead commit citations -- but nothing resolves `[[...]]` targets. The
existing `DEAD-COMMIT` check is the exact precedent: it exists because a
citation pointing at nothing is worth catching, and it covers only shas.

## Mechanism, with a worked example that is mine

These are written from memory of what a ticket is *about* rather than from its
filename. Mine, filed yesterday: I cited a Track T ticket as
`...-a-skipped-lib-test-job-reports-green-and-manufactures-a-false-last-good`
when the ticket I had just written that day is
`bug-t-a-skipped-job-is-passlike-so-it-becomes-a-false-last-good`. Both describe
the same defect; only one is a filename. Fixed in the same commit as this
ticket.

That is why the count is 52 rather than a handful -- the failure needs no
carelessness, only a descriptive slug and a writer who remembers the subject.

## Fix sketch

A `check` rule beside `DEAD-COMMIT`: resolve every `[[target]]` under
`devdocs/progress/**` against the set of ticket basenames, ignoring the
`project_*` / `feedback_*` memory namespaces and devdocs filenames, and report
the unresolved ones -- loudest for links in live tickets, since a dead trail in
`done/` is history and a dead trail in `backlog/` is a live obstacle.

Worth deciding rather than guessing: whether unresolved links should fail
`check` or only warn. The 52 existing ones argue for warn-first, or the rule
lands red on day one and gets ignored, which is the usual fate of a check that
starts failing.

## Gate

Track T's own: the quick tier green, plus the new rule reporting a
known-dangling link and staying silent on a resolving one -- negative-controlled
in both directions, because a checker that reports nothing looks identical to a
clean board.
