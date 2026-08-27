---
track: W
prio: 40
type: feature
blocked-by: []
summary: "pxxc.org serves no `/llms.txt` (404) and no JSON-LD structured data. The site is otherwise unusually legible to machines — server-rendered, indexed, and summarised ACCURATELY including the byte-identical discipline holding under compression — so these two files are the remaining gap in a channel that already works, not a rescue job."
status: backlog
---

# No `/llms.txt` and no JSON-LD — the machine-readable description is missing

Found 2026-08-27 while checking whether pxxc.org is legible to non-browser
fetchers. **Fix lands in the private `~/pxx-website` repo, not this checkout.**

File this as a *completion* item, not a repair one. The audit came back better
than expected and the passing results below are worth recording, because they
tell whoever picks this up what NOT to go rebuild.

## What already works — do not "fix" these

| property | result on 2026-08-27 |
| --- | --- |
| server-rendered HTML | **yes** — 7800 bytes, complete content, zero JS needed |
| SPA shell risk | **none** — `curl` gets the same text a browser shows |
| `<title>` / `meta description` | present, accurate |
| `canonical` | present |
| `og:` / `twitter:` text tags | present (but no image — [[bug-web-link-previews-render-as-bare-text]]) |
| `robots.txt` | `Allow: /`, declares the sitemap |
| `sitemap.xml` | HTTP 200, 55 URLs |
| already indexed | **yes** — a cold web search surfaced `/`, `/contribute/`, and a deep `/status/done/<ticket>/` page |

The SPA-shell check was the one that gated everything else, and it passes
outright. Agent fetchers, unfurlers and search crawlers all get real content.

## The result worth keeping

A small summarising model was pointed at the landing page and asked point-blank
whether the page claims byte-identity with another compiler. It answered:

> makes **no claims about byte-identical output** to other compilers, though it
> notes the project is "verified against gcc / fpc / cpython as oracles."

That is the exact outcome `CLAUDE.md`'s claims-discipline section is written to
produce, surviving the hard case — a compressor with every opportunity to drop
the qualifier, which it could not do because the page never offered a
pre-compressed version to grab. **Whatever the landing page is doing here, keep
doing it**, and treat it as the standard the new files below must also meet.

The Limitations block ("about 2x slower than FPC, gcc, or CPython") is likewise
an asset, not a liability: summarisers repeat it verbatim, and a page that
states its own weakness reads as trustworthy. Do not soften it.

## The two gaps

### 1. `/llms.txt` returns 404

Verified: `curl -o /dev/null -w '%{http_code}' https://pxxc.org/llms.txt` -> 404.

A stable machine-readable summary at a conventional path. This is the correct
form of "make the project legible to agents" — the substance of that idea
without any of the agent-forum-posting nonsense. Contents should be a short
Markdown digest: what pxx is, the frontends, the targets, the honest
limitations, and links to `/docs/`, `/compliance/`, `/status/` and the GitHub
repo.

Write it uncompressed. `llms.txt` exists specifically to be read by a
summariser, so it is the file where a dropped qualifier does the most damage —
the whole claims-discipline section of `CLAUDE.md` applies at full strength.

### 2. No JSON-LD structured data

Verified: no `application/ld+json` anywhere in the rendered head or body.

Add a `SoftwareApplication` or `SoftwareSourceCode` block: name, description,
`codeRepository` (`https://github.com/yoctobyte/pxx`), `programmingLanguage`,
`license` (MPL-2.0 for the core, per the repo's per-directory licensing),
`operatingSystem`, and the CPU targets. This is what search and assistant
surfaces read to answer "what is pxx" without fetching and re-summarising the
prose every time.

## What this does NOT fix

Neither file addresses the actual discovery gap: pxxc.org ranks for the string
"pxx" and essentially nothing else. A cold search for the project returned
Wikipedia and Fandom pages about *other* Pascal compilers as the competing
results. Nobody searches "pxx" — they search "Pascal compiler ESP32",
"self-hosting compiler", "compile C without libc". Getting into those is an
authority-and-citations problem solved by things worth citing, not by on-site
metadata. See [[feature-web-blog-bootstrap]].

## Gate

`/llms.txt` returns 200 with the digest; JSON-LD validates; re-run the
summariser check above and confirm the byte-identical discipline still holds in
the answer.
