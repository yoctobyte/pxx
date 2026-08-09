---
prio: 25
blocked-by: [feature-web-track-w-bootstrap]
---

# Track W (website) — filed-vs-solved ticket flow graphs, per track

- **Type:** feature (website content)
- **Track:** W (website) — a site page, not `docs/**` prose. Follows the
  public-board rule from [[feature-web-track-w-bootstrap]]: feature/content/UI
  tickets live here, nothing security-sensitive.
- **Status:** done
- **Owner:** trackW-agent

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

## Built 2026-08-09

Live at `/status/flow/` on pxxc.org. Three panel groups, all small multiples
per track: filed-vs-closed, open-over-time, and open-tickets-by-age.

**Generator:** `tools/ticket_flow.py` in this repo, emitting the committed
`devdocs/progress/ticket-flow.json`; declared windows live in
`devdocs/progress/sweeps.json`. Re-run it after resolving tickets — the page
shows the generation date precisely because it is a snapshot, not a live query.

It has to be committed JSON rather than computed by the site: the website's
content checkout is `git clone --depth 1`, so it has the ticket files but no
history at all and cannot see a filed date. Track is read via `progress.py`'s
`Ticket.track` rather than reimplemented — that property carries every
hard-won special case, and the point of the field-not-filename rule is lost if
a second parser guesses.

**Ownership note (the ticket's own instruction):** the generator landed under
`tools/` and is not smuggled in as content — it is W's data pipeline living in
the public repo, where the ticket asked for it. It is not in Track T's
enumerated tool list, and it writes into `devdocs/progress/**`, so if the board
owners want it re-homed to A/B that is a one-line move and this note is the
flag for it.

### Two things the data forced

1. **The board's founding day is an import, not discovery.** 2026-06-26 wrote
   down 398 tickets at once for work in flight since 2026-05-24 — 20% of the
   whole board on one day. Plotted, it alone sets Track A's axis to 308/day and
   presses the real ~8/day rate flat against the baseline: a chart whose only
   legible feature is a bookkeeping artifact. Declared as `kind: import` and
   excluded from the filed-vs-closed panels, with the exclusion stated on the
   page. The open-over-time panels keep those tickets, because they genuinely
   were open from that day on.
2. **Colour cannot encode the track.** Seven lanes clear the 40-ticket floor,
   and the site's seven validated hues FAIL all-pairs shown together (orange vs
   green ΔE 3.2 protan; orange vs magenta 12.9 normal-vision). The largest
   subset passing light AND dark is four. So identity moved to the panel title
   and colour carries filed-vs-closed — blue/green, all checks pass in both
   modes, worst ΔE 26.5.

### Panels 1-3 of the four suggested; panel 4 is not built

Cross-track spillover — "Nil-Python work filed 82 Track A tickets" — is still
the best story here and is NOT done. It needs a reliable reference edge between
tickets, and the `[[slug]]` links are not consistently present. Worth its own
ticket rather than a weak version of it under this one.

### Sweep declaration is deliberately manual

A sweep is a claim about INTENT, and no curve-fit recovers intent from a spike.
The generator warns about undeclared spikes but never invents a band. There is
currently 1 outstanding — the page says so, so an unexplained step reads as
unexplained rather than as meaning something.

## Log
- 2026-08-09 — built and deployed. Panels 1-3 done, panel 4 (cross-track
  spillover) explicitly not attempted; the founding-day import and the
  seven-hue palette failure are both recorded above because both would
  otherwise be re-discovered by whoever touches this next.
- 2026-08-09 — resolved, commit PENDING-COMMIT.
