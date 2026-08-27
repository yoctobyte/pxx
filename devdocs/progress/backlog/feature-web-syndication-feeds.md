---
track: W
prio: 30
type: feature
blocked-by: [bug-web-production-tree-is-uncommitted-and-is-the-only-copy]
summary: "The site publishes two things that change continuously — the `Latest resolved` ticket list and (once it exists) the blog — and offers no RSS/Atom feed for either. No `application/rss+xml` or `application/atom+xml` link anywhere in the head. A follower has no way to follow, and the one genuinely novel asset (a live public record of a compiler being built by an agent fleet) is unsubscribable."
status: backlog
---

# No RSS/Atom feed for the blog or the resolved-tickets stream

Found 2026-08-27 during the machine-legibility audit
([[feature-web-machine-readable-project-metadata]]).
**Fix lands in the private `~/pxx-website` repo, not this checkout.**

## The measurement

`curl -sSL https://pxxc.org` on 2026-08-27:

- no `application/rss+xml` link
- no `application/atom+xml` link
- the landing page renders a **`Latest resolved`** block — five tickets dated
  2026-08-27 at the time of checking, including one auto-filed by twatch
- `/blog/` returns 200 and reads `Coming soon.`

So the site already *produces* a dated, continuously-updating stream and simply
does not expose it in the one format built for following a stream.

## Why this is worth more here than on a typical project site

The `Latest resolved` list is not a changelog. It is a public, timestamped,
independently-verifiable record of a compiler being developed by a fleet of
parallel agents, including regressions the watcher filed against itself without
a human in the loop. That is the project's most distinctive artifact and
nothing else on the open web looks quite like it.

A feed turns that from a page someone visits once into something they follow.
It is also the format aggregators, planets, bots and assistant surfaces
actually poll — which makes it the second correct answer, after `llms.txt`, to
"how do we reach an audience that is increasingly not a human with a browser".

## What to do

1. Emit an Atom feed for resolved tickets — id, title, `updated`, the ticket's
   permalink under `/status/done/<slug>/`, and the ticket summary as content.
   Cap it at the most recent N; the archive is already browsable.
2. Emit a second feed for `/blog/` when the blog lands
   ([[feature-web-blog-bootstrap]]). Keep them separate — someone who wants
   long-form posts does not want fifty ticket resolutions a week, and
   conflating them guarantees unsubscribes from both.
3. Declare both with `<link rel="alternate" type="application/atom+xml">` in
   the head so readers and bots autodiscover them.
4. Link them visibly from the footer as well; autodiscovery alone is invisible
   to a human who wants to subscribe.

## Note on the ticket feed's content

Ticket titles and summaries become public-facing prose the moment they are
syndicated — they already are, since `/status/done/<slug>/` pages are indexed
(a cold web search surfaced one). Worth knowing when writing a `summary:` line;
this is not a reason to write them differently, just a reason to know.

## Gate

Both feeds validate, autodiscovery resolves in a reader, and the ticket feed's
entries match what `/status/` shows.
