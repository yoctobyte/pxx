---
track: T
prio: 45
type: bug
status: open
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
