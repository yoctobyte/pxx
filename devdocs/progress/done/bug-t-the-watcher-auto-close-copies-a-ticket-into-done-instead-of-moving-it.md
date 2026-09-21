---
track: T
prio: 45
type: bug
status: done
found: 2026-09-01
found-by: claude-C
owner: ""
blocked-by: []
summary: "The seven watcher's auto-close writes the ticket into done/ and leaves the backlog/ copy in place, so the slug exists twice. Measured 2026-09-01: 2ade3f11b closed three regressions that way and all three stayed in backlog/. Effects are silent — the board double-counts, ready/next keep offering closed work, and `progress.sh resolve` fails with `ambiguous slug` for anyone who tries to close it by hand. Three duplicates at the time of filing, all from that one commit; fixed by hand in the same commit as this ticket, but the mechanism will reproduce on the next auto-close."
---

# The watcher's auto-close copies a ticket into `done/` and leaves the original

`2ade3f11b` ("tstate-ticket(seven): closed … (job green again)") wrote
`devdocs/progress/done/<slug>.md` for three regressions and did NOT remove
`devdocs/progress/backlog/<slug>.md`. Both copies are tracked, and the `done/`
one is the backlog one plus an auto-close `## Log` entry — so the content is
right and only the MOVE is missing.

## How it surfaces, which is the reason to fix it rather than just clean up

Nothing errors. Three separate consumers quietly disagree instead:

- **`ready` / `next` keep offering closed work.** This is how I found it:
  `next --track A` handed me a regression as the top entry point and it had
  already been fixed. A stale row in the ranker keeps its filed priority
  forever, so it outranks live work indefinitely.
- **The board double-counts** — one ticket, two rows, two statuses.
- **`progress.sh resolve` refuses**, and this is the only LOUD symptom:
  `ambiguous slug <name> — matches: …/backlog/<name>.md …/done/<name>.md`.
  A human closing the backlog copy by hand hits an error whose text does not
  say "the watcher already closed this".

## Measured

```
duplicated across backlog/ and done/ : 3
  regression-test-core-c-crtl-enosys-stubs
  regression-test-core-test-header-static-body
  regression-test-core-test-thread-api-no-uses
duplicated across any other status folder and done/ : 0
```

All three from `2ade3f11b`. The blast radius is that one commit's ticket set, so
this is recent rather than long-standing — worth fixing before the next
auto-close adds more.

## The fix

Wherever the watcher writes the `done/` copy, remove the source path in the same
commit (a `git mv`, or the write plus a `git rm`). Then add the check that would
have caught it: **no slug may exist in two status folders.** That is a one-line
invariant over `devdocs/progress/*/`, it is cheap, and it has a real positive
control available — `2ade3f11b^..2ade3f11b` is a commit it must reject.

Note for whoever writes it: `comm -12` over two `ls` outputs needs
`LC_ALL=C sort` on BOTH sides. Without it `comm` prints
`file 2 is not in sorted order` to stderr and an UNDERCOUNT to stdout, and the
undercount looks like a clean answer. My first census reported 2 duplicates that
way; the real number was 3.

## Cleaned up by hand in the filing commit

The three backlog copies are removed and my verification notes were appended to
the `done/` copies first, so nothing is lost. The mechanism is untouched and
will reproduce.

## Deprioritised 2026-09-02 — the Track T tooling backlog was cut as a pile

**This ticket is not being called wrong.** It was moved as part of a pile, not
judged individually, and nothing here disputes its finding.

Owner decision. 73 of the 74 open `track: T` tickets were filed between
2026-08-31 and 2026-09-02, 58 on one day. The pile was too large to work through
and returned almost nothing, and a ticket nobody will fix does not sit neutrally
— it stays in the ranker forever at zero value, which is the argument CLAUDE.md
already makes for a terminal folder over a low prio.

Four were kept in the ranker on a purely structural test — an active umbrella or
a hard `blocked-by:` edge from live work:
`umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**Kept, not deleted, for two reasons:** so the finding is not rediscovered and
refiled from scratch by the next agent who trips over it, and so it can be pulled
back if what it touches becomes load-bearing.

**To revive it:** move it to the owning lane's backlog, set `status: backlog`,
and say in the ticket WHAT CHANGED to make it matter now. Restoring it because it
reads well is how the pile comes back.

## Log
- 2026-09-21 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit e1466217d.

## Resolution (2026-09-21, borg Track T)

Root cause, reproduced in a scratch clone and guarded:
`close_stub_tickets()` unlinked each closed stub's backlog copy INSIDE its
loop, then published twice — the annotated set ("green but NOT closed")
first, the closed set second. The first publish's recovery path
`_drop_to_origin()` runs `git reset --hard origin/<branch>`, which RESTORES
every backlog copy already unlinked. The close publish then computes its
`gone` list from a tree where the file exists again, stages no deletion, and
the ticket lands in `done/` while staying ranked in `backlog/`.

`publish()` already re-asserts deletions its own `git checkout` undid
(ee4553627) — but only for the paths IT was given, and the annotated publish
is a different call with a different path list. That is why the two earlier
fixes did not cover this and why it is intermittent: it fires on the CYCLE
MIX (a retry-class job going green alongside an ordinary one, plus a rebase
conflict, which is ordinary on a busy origin), not on anything about the
ticket.

This also explains the 2026-09-04 report, whose two candidate causes were
both excluded by measurement — correctly, because neither was it. Both
excluded candidates were about the state `src` was computed from; the fault
is a SECOND publish in the same call.

Fix: defer the unlinks until after the annotated publish, immediately before
the close publish. `tools/twatch.py`.

Guard: `tools/twatch_close_stubs_devtest.py` case 8 — annotate + close in one
cycle with the clone DETACHED (the state every case before it was missing,
and the state the daemon is always in when it decides). It asserts the
ticket's own positive control: NO file with that slug outside the terminal
folders. Verified to FAIL on the unfixed code and pass with the fix; the
"done/ copy appeared" assertion beside it passes either way, which is what
made this survivable for three weeks.

Inert until the daemon restarts: the watcher holds the code it was STARTED
with (its published fingerprint said cead35240, 2026-09-11). The duplicates
already on origin were swept by hand on 2026-09-19 and are not re-created by
this change.
