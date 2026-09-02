---
track: T
prio: 60
type: bug
status: open
found: 2026-09-02
found-by: frank-user
---

# The ranker reads frontmatter; some tickets announce resolution only in the body

summary: "A ticket whose BODY says it is fixed while its `status:` frontmatter
still says `backlog` stays in the ranker forever, and `ready`/`next` keep
handing it out. frankZ hit one live on 2026-09-02 — conformance shard0 was
claude-T's fix from 09-01, still wired as an umbrella blocker three days later
because the body said RESOLVED and the frontmatter did not. A loose scan finds
~15 candidates across the open folders, but that NUMBER IS NOT TRUSTWORTHY and
must not be quoted: 1 of 3 sampled was a false positive (`**fixed** 120s
ceiling` — the word as an adjective, in a ticket with no `status:` line at all).
Two of three were genuine. The work is a sound predicate and then the sweep,
not the sweep."

## Why this costs more than it looks

The ranker reads frontmatter. A human reads the body. So the two disagree
silently and in the direction that WASTES A SESSION: the ticket looks open to
every tool, and whoever picks it up discovers it was fixed days ago. frankZ's
umbrella spent its Group 1 effort establishing exactly that for two of four
tickets — the causes were real, and both had already been fixed, one of them by
the owner six hours after filing and then left open three days at prio 70.

This is the same family as `**Track:** X` body markdown versus the `track:` YAML
field, which `tools/ticket_age.py` had to learn to read both of.

## What a sound predicate needs

- `## Fixed <date>` and `**Fixed at `<sha>`**` as HEADINGS or leading bold are
  strong; the bare word anywhere in prose is not.
- A resolution citation (`resolve` writes a dated line naming a commit) is a
  better signal than any adjective.
- Tickets with NO `status:` field at all are a separate defect and should be
  counted separately, not swept in — one of the three sampled had none.

## The positive control

The sweep must be run against a ticket KNOWN to be correctly open and a ticket
KNOWN to be stale-open, and reject the first while flagging the second. Drawn
from the open folders, not a fixture. A scan that flags everything containing
"fixed" passes on a corpus where most tickets mention the word — which is how
the loose number above was produced.

## Related

frankZ's closing observation from four umbrella groups on 2026-09-02, which is
the reason this is filed at 60 rather than 25: **of the causes it found, more
were STALE PAPERWORK than live bugs** — a resolved ticket with backlog
frontmatter, two `pxx.skip` rows asserting a capability the compiler had gained
three days earlier, a filer routing Pascal-frontend defects to a lane that
cannot fix them, and an expectation nobody had executed. The compiler was right
in four of those; the record was wrong.
