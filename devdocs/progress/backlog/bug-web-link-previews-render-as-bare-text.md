---
track: W
prio: 45
type: bug
blocked-by: []
summary: "NOT DEPLOYED — visitors still get twitter:card=summary and no og:image. The fix is committed and reviewed as e78595d on the website repo but has not been pulled onto `via`, so it is in git and not on the wire; do not read `committed` as `live`. Originally: pxxc.org declares og:title/og:description/og:url but NO og:image, and twitter:card is `summary` rather than `summary_large_image`. Every link to the site on HN, Reddit, Mastodon, Slack, Discord and LinkedIn renders as a bare text row next to posts that have a picture. Highest click-through gain per hour of work on the site; the fix is one image plus two meta tags."
status: backlog
---

# Link previews to pxxc.org render as bare text — no `og:image`

Found 2026-08-27 while checking whether the site is legible to non-browser
fetchers (agent crawlers, link unfurlers, search summarisers). The fetchability
verdict was good — see
[[feature-web-machine-readable-project-metadata]] for what was still missing —
but the social-card surface is empty.

**Fix lands in the private `~/pxx-website` repo, not in this checkout.**

## STATUS 2026-08-27 — IN GIT, NOT ON THE WIRE. Do not read this as live.

**What visitors get right now: the pre-fix tags.** `twitter:card=summary`, no
`og:image`. A link to pxxc.org still unfurls as a bare text row. That is the
one line to carry forward — a future session reading "p45 committed" will
reasonably assume the site serves a card, and it does not.

State from the origin side, reported by `ianweb` on `via` (the only session that
can observe it):

| | |
| --- | --- |
| `origin/main` | `e78595d` — p45 committed, reviewed line-by-line, recommended |
| `via` HEAD | `d7b36d845` — 0 ahead / 0 behind; the fix is **fetched but unmerged** |
| what visitors get | **still the pre-p45 tags** |
| blocking step | the manual deploy gate, with the human |

**Three distinct states, and the middle one is where this sits:** committed →
reviewed-and-fetched-but-not-merged → served. Only the third changes what
anyone sees.

**Why it is not deployed, and why that is correct.** `deploy/DEPLOY-STATUS.md`:
*"Deploys stay manual on purpose: auto-deploy would let a compromised GitHub
account run code on the host."* An agent pushing a commit and then asking the
agent on the host to pull it is structurally what that gate exists to stop —
benign here, since `ianweb` read every line and recommends it, but "I checked
and it's fine" is precisely what the gate is designed not to depend on. It is
the same reasoning that kept push keys off `via`, pointed the other way down the
same pipe.

**Remaining steps, neither of them a coding task:**

1. A human go/no-go on the deploy.
2. `git pull` on `via`, then `sudo systemctl restart pxxweb` — Jinja caches
   compiled templates in the worker, so a pull alone changes nothing served.
3. The rendered `<meta>` lines captured from the origin and pasted into this
   ticket. An outside audit cannot distinguish "not deployed" from "deployed and
   edge-cached", so this verification has to come from `via`.

**This ticket resolves on step 3, not on the commit.** Everything about the p45
is done except the one step that makes it real.

## What landed (for the record)

Fixed in the website repo as **`e78595d`** ("Link previews: an Open Graph card,
and the large-image Twitter card"), pushed to `origin/main`.

- `pxxweb/static/img/og-card.png` — 1200x630, new directory
- `pxxweb/templates/base.html` — `og:image` (+ width/height/alt),
  `twitter:image`, and `twitter:card` raised to `summary_large_image`
- `scripts/make-og-card.py` — the card is generated, not hand-drawn, so a copy
  change is a one-line edit and a re-run

**Not closed yet, deliberately.** Two steps remain and neither is mine:

1. **A gunicorn restart on `via`.** Jinja caches compiled templates in the
   worker, so `git pull` alone does not change what visitors are served. Until
   that happens the tags are in git and not on the wire.
2. **Confirmation of the served result, from the origin.** An outside audit
   cannot distinguish "not deployed" from "deployed and edge-cached", so the
   check has to come from `via`. `ianweb` has it.

Safe to land ahead of
[[bug-web-production-tree-is-uncommitted-and-is-the-only-copy]] because the
edit was made in a clean clone and pushed, not made on `via`. `ianweb` verified
the part only it could: `git diff --name-only` on `via` does not list
`base.html`, so the pull fast-forwards cleanly and leaves the six uncommitted
files alone. That is also why this ticket and its three siblings no longer
declare the p70 as a blocker — see that ticket for why the premise narrowed.

**Do not overwrite `og-card.png` in place.** nginx serves `static/` with
`expires 1h` and no fingerprint in the URL, so a new file needs no purge but a
replaced one is served stale from the edge for up to four hours. Ship a new
filename and update the template instead.

## The measurement

`curl -sSL https://pxxc.org` on 2026-08-27, grepping the rendered `<head>`:

| tag | present? | value |
| --- | --- | --- |
| `og:type` | yes | `website` |
| `og:site_name` | yes | `pxx` |
| `og:title` | yes | `pxx — a fresh Pascal compiler` |
| `og:description` | yes | the full one-liner, accurate |
| `og:url` | yes | `https://pxxc.org/` |
| **`og:image`** | **NO** | — |
| `twitter:card` | yes | **`summary`** |
| `twitter:title` / `twitter:description` | yes | mirror the og: values |
| `link rel=icon` | yes | `/static/favicon.svg`, SVG only |

So the metadata is otherwise complete and correct — this is a single missing
asset, not a neglected head section.

## Why it matters more than it looks

Unfurlers fall back to a text-only row when `og:image` is absent. On the
channels where a compiler project actually gets discovered — HN, Reddit,
lobste.rs, Mastodon, a Slack or Discord where someone pastes the link — that
row sits directly beside entries that carry a picture, and it loses the
comparison every time. `twitter:card: summary` compounds it: even once an image
exists, `summary` renders a small thumbnail, where `summary_large_image` gives
the wide card.

This is the cheapest real gain available on the site right now. It does not
improve the page for anyone already reading it; it improves the odds that
someone clicks through at all.

## What to do

1. Author an OG card image, 1200x630, and serve it from `/static/`. It must
   read at thumbnail size — the project name plus one line, not the landing
   page's full feature list shrunk down.
2. Add `<meta property="og:image" content="https://pxxc.org/static/og.png">`
   (absolute URL — several unfurlers do not resolve relative ones), plus
   `og:image:width` / `og:image:height` / `og:image:alt`.
3. Change `twitter:card` to `summary_large_image`.
4. Consider a PNG favicon alongside the SVG; a few older unfurlers and
   browsers ignore `image/svg+xml`.

## Claims discipline applies to the card

The card image is public-facing copy in the sense
`CLAUDE.md` means it, and it is the *most* compressed surface the project has —
a headline with no room for qualifiers. So it must not carry any form of the
byte-identical claim. "Self-hosting Pascal and C compiler" is safe; anything
about matching gcc is not, at any length that fits on a card. The landing page
currently gets this right and a summariser confirmed it (see
[[feature-web-machine-readable-project-metadata]]); the card is where that
discipline is most likely to be lost first.

## Gate

Fetch the page, confirm the tags are present, and validate the rendered card
against at least two unfurlers before closing.
