---
prio: 25
track: A
blocked-by: []
---

# `progress.sh check` should flag a ticket that declares its track only in prose

- **Type:** chore (board hygiene / tooling)
- **Track:** A (owns `tools/progress.py`)
- **Status:** backlog — split out of [[meta-track-w-collision-windows-vs-website]] 2026-08-08
- **Owner:** —

## Why

Two conventions exist for declaring a ticket's track: frontmatter `track:` and a
`- **Track:**` body line. `progress.py` reads the frontmatter first and falls
back to prose, so both work — but the split is exactly what let the W collision
hide for months. Windows declared `track: W` in frontmatter; the website wrote
`- **Track:** W (website)` in prose. A `grep "^track: W"` found only Windows; a
prose search found only the website. **Neither search showed the conflict.**

The fallback is doing real work today and must NOT be removed: ~130 live tickets
carry no frontmatter `track:` at all and are resolved correctly by prose. So the
fix is a warning, not an error, and not a mass backfill.

## What

`tools/progress.sh check`: for each live ticket whose track resolves ONLY via
the prose fallback, print one line. Suggested shape:

```
prose-only track (add `track: X` to frontmatter): feature-web-track-w-bootstrap -> W
```

Then a follow-up (or the same pass with a `--fix` flag) can backfill the
frontmatter, after which the count trends to zero and a new collision is
visible to a single grep.

**Do not fail `check` on it** while the count is ~130 — that would make `check`
permanently red, which is worse than the problem. Warn, count, and let the
number come down.

## Watch for

A ticket where frontmatter and prose DISAGREE is a different, sharper bug than a
missing field — worth its own louder line, since one of the two is a lie and the
ranker silently picks the frontmatter.
