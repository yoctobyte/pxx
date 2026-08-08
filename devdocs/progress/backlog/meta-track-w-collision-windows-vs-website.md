---
prio: 45
blocked-by: []
---

# Track letter W is claimed by TWO lanes — Windows and Website

- **Type:** meta (board hygiene / coordination hazard)
- **Track:** A (the board belongs to A/B)
- **Status:** backlog — found 2026-08-08
- **Owner:** —

`W` currently means two different things, and the two halves hid from each
other because they are spelled differently — which is why this went unnoticed:

| claimant | how it declares the track | tickets |
| --- | --- | --- |
| **Website** | body line `- **Track:** W (website)` | `feature-web-track-w-bootstrap`, `chore-web-secrets-sops-age`, `feature-web-tracker-and-host-portability`, plus references from `done/` |
| **Windows** | FRONTMATTER `track: W` | `feature-port-windows-pe`, `feature-t-windows-wine-harness`, `feature-pcl-tk-windows-compat`, `feature-pcl-win32-widgetset` |

A `grep "^track: W"` finds only Windows. A prose search finds only Website.
Neither search shows the conflict.

## Recommendation: Website keeps W; Windows was never a lane

**Website has the stronger claim, and it is documented.**
[[feature-web-track-w-bootstrap]] (2026-07-12, user + agent) argues the letter
explicitly against CLAUDE.md's "don't invent letters" rule and passes that
rule's own test: the bar is *a genuinely new place code lives*, and the website
is a separate private repo. Precedent cited there: Track T's watcher runs in
its own clone and is still a track. That reasoning stands.

**Windows does not meet the same bar.** There is no "why a new letter" note for
it anywhere, and it is not a place code lives — it is a campaign spread across
existing lanes:

- `feature-port-windows-pe` (PE/COFF writer, MS x64 ABI) → **Track A**
- `feature-pcl-win32-widgetset`, `feature-pcl-tk-windows-compat` → **Track B**
- `feature-t-windows-wine-harness` → **Track T**

That is precisely the shape of **S (eSpressif/SoC)**: a work-tag surfaced as a
visible campaign, file-owned per ticket by A/B/T and gated by that lane. Windows
should be the same. If it wants a visible letter, it needs a free one and a
recorded rationale — not W.

## Second finding: `progress.sh` knows NEITHER

```
--track: invalid choice: 'W' (choose from A,B,C,D,E,N,O,P,R,S,T,U,Z)
```

So the four Windows tickets carry a frontmatter track the ranker does not
recognise, and the website tickets were never in the frontmatter system at all.
Both sets are effectively invisible to `next`/`ready`. Whatever letters survive
must be added to the tool, or the tickets do not exist as far as the queue is
concerned — which is likely why nobody hit the collision by working on it.

## Third finding: two conventions for declaring a track

Frontmatter `track:` versus a `- **Track:**` body line. The ranker reads the
first; humans write either. That is what let the collision hide, and it will
hide the next one too. Pick one (frontmatter, since it is machine-read) and have
`progress.sh check` flag a ticket that declares a track only in prose.

## Do NOT retro-edit `done/`

Several closed tickets reference "the website (Track W)". Those are historical
records of what was true when written; correcting them falsifies history
(CLAUDE.md, precedence rule). Fix live tickets and the tooling; leave the record
alone.

## Log
- 2026-08-08 — found while filing a website ticket. The agent grepped frontmatter,
  found only Windows, and "corrected" the user's (accurate) statement that W was
  the website lane. The user pushed back from memory and was right. Filed rather
  than fixed on the spot because it overturns a considered decision and touches
  ~8 tickets.
