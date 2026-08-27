---
track: W
prio: 45
type: bug
blocked-by: []
summary: "pxxc.org declares og:title/og:description/og:url but NO og:image, and twitter:card is `summary` rather than `summary_large_image`. Every link to the site on HN, Reddit, Mastodon, Slack, Discord and LinkedIn renders as a bare text row next to posts that have a picture. Highest click-through gain per hour of work on the site; the fix is one image plus two meta tags."
status: backlog
---

# Link previews to pxxc.org render as bare text — no `og:image`

Found 2026-08-27 while checking whether the site is legible to non-browser
fetchers (agent crawlers, link unfurlers, search summarisers). The fetchability
verdict was good — see
[[feature-web-machine-readable-project-metadata]] for what was still missing —
but the social-card surface is empty.

**Fix lands in the private `~/pxx-website` repo, not in this checkout.**

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
