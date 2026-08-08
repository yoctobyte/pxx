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

**Concrete proposal (user, 2026-08-08): `M` = MSWindows, as a TAG.** M is
genuinely free — verified against BOTH declaration conventions, which is the
check that would have caught this collision in the first place. Claimed today:
A B C D E N O P S T U W Z. Free: F G H I K L M Q V Y. (`R` is declared in
CLAUDE.md but carried by no ticket; the Rust work sits in `experimental/`,
which is unranked by design.)

The tag rule applies exactly as it does to O and S: an M ticket ALSO carries
its Track A / B / T file-ownership for collision purposes and obeys that lane's
gate. `*-windows-*` / `*-win32-*` / `*-wine-*` slugs would auto-tag M, same as
`*-esp-*` does for S. Retagging the four is then a frontmatter edit plus a
CLAUDE.md entry, not a reorganisation.

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

## The retag also has to fix CROSS-REFERENCES

Retagging the four Windows tickets is not enough — other tickets name the lane
in prose and would keep pointing at the wrong one. Known today:
`rainy-day/feature-os-targets-bsd-mac.md` says "[[feature-port-windows-pe]]
(Track W)". Grep for `Track W` in live tickets as part of the change, not after.

That ticket also carries NO track field at all, so it is invisible to the
ranker for the same reason the W tickets are — worth sweeping for while in here.

## Future platform campaigns take the same shape (2026-08-08)

BSD and macOS will raise this again and the answer is already settled by the
S/M precedent: **one tag per FAMILY, not per variant.** S covers ESP32/S2/S3/C3
with the variant named in the ticket text; a BSD tag would cover
Free/Open/Net/Dragon the same way. The apparent letter shortage (A=Apple,
O=OpenBSD, F=FreeBSD all colliding or ambiguous) is an artifact of assuming one
letter per OS.

Deferring is FREE, and that is worth stating because it is not obvious: a lane
cannot be deferred (exclusive file ownership must be declared before two agents
collide), but a tag can, because it is a view over tickets that already exist.
It can be minted later and applied retroactively by slug pattern. BSD/macOS work
can land as A/B/T today and be grouped whenever the board has enough rows to
want it.

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
