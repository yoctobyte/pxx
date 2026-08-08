---
prio: 25
blocked-by: [feature-web-track-w-bootstrap]
---

# Track W (website) — filed-vs-solved ticket flow graphs, per track

- **Type:** feature (website content)
- **Track:** W (website) — a site page, not `docs/**` prose. Follows the
  public-board rule from [[feature-web-track-w-bootstrap]]: feature/content/UI
  tickets live here, nothing security-sensitive.
- **Status:** backlog — idea 2026-08-08
- **Owner:** —

A published chart of tickets **filed** against tickets **closed**, bucketed by
week and split by track, so the project's defect curve is visible rather than
anecdotal. The interesting shape is the **bump**: a frontend goes through a
period of filing faster than fixing, peaks, and turns over. Pascal, C and
Nil-Python have each done it; showing three curves at different phases says
more about the project's maturity than any feature list.

## The data already exists — no new bookkeeping

Measured 2026-08-08, works today:

- **Track** — the `track:` field in each ticket's frontmatter. Read the FIELD,
  never the filename (`feedback_check_ticket_track_field_not_filename`).
- **Filed date** — first commit touching that basename under
  `devdocs/progress/`.
- **Closed date** — first commit where its path is under `done/`.
- **Kind** — `bug-`/`regression-` prefix versus everything else; the bug ratio
  is the meaningful one, features distort it.

One `git log --reverse --date=short --format=... --name-only -- devdocs/progress`
pass yields all of it. Renames across status dirs are handled by matching on
basename rather than path, which is why `--follow` (slow, per-file) is not
needed.

Sample of what it produced for Track N, to show the shape is real:

| week of | bugs filed | bugs closed | filed per closed |
| --- | --- | --- | --- |
| 07-13 | 6 | 4 | 1.50 |
| 07-20 | 24 | 21 | 1.14 |
| 07-27 | 188 | 142 | 1.32 |
| 08-03 | 79 | 106 | **0.75** |

## The caveat that MUST be on the chart

**Sweeps distort the curve and will be misread without a marker.** A deliberate
bulk-discovery campaign (the CPython differential sweep, 2026-07-28..08-02,
peaking at 45 bugs filed in a day) front-loads filing, so the curve reads as
"the code got much worse, then much better" when nothing of the sort happened.
Mark sweep windows as shaded bands, or the graph tells a false story about the
project — which is worse than not publishing it.

Related honesty: a falling filed-rate cannot distinguish *fewer bugs exist*
from *we stopped looking*. If the page draws a conclusion, the defensible one
is sweep-over-sweep (does the next campaign find fewer than the last?), not
week-over-week.

## Suggested panels

1. Filed vs closed per week, per track, small multiples — the bump, three times.
2. Net open over time (the running integral) — one line per track.
3. Age of currently-open tickets, bucketed — the "working queue vs graveyard"
   check. Track N on 2026-08-08: 28 of 56 open were ≤7 days old, 7 were >14.
4. Optional and probably the best story: **cross-track spillover** — tickets in
   OTHER tracks that reference a given frontend's work. Nil-Python work filed
   82 Track A tickets, 9 Track P, 6 Track C. That is the "a new frontend hardens
   the shared IR for every later frontend" claim, as a number.

## Shape / constraints

- **No compiler, no `lib/**`, nothing rebuilt** — this is content.
- The source data lives in the PUBLIC repo (`devdocs/progress/**`), and the
  chart is derived, so the generator belongs on the public side: a script that
  reads the board and emits a committed SVG or JSON, with the site rendering it.
  Keeps the private repo out of the loop entirely and keeps the numbers
  verifiable, which is the stated reason docs/releases are public at all.
- If that generator lands under `tools/`, file it separately in the owning lane
  rather than smuggling tooling in under a content ticket.
- Numbers on a public page are a claim. Keep the two "byte-identical" senses
  straight and do not let a chart imply the wrong one (CLAUDE.md, claims
  discipline).

## Notes

- Idea from the user, 2026-08-08, while reviewing whether Nil-Python was "over
  the bump". The answer needed exactly this chart and it had to be computed by
  hand, which is the argument for building it.
