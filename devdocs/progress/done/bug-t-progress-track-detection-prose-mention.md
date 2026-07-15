---
summary: "progress.py track() matches a prose 'Track T' mention in the Type/Track bullet before the authoritative frontmatter track: field — mis-tags tickets (3 hit in one session)"
type: bug
track: T
prio: 40
---

# progress.py mis-tags tickets when the Type/Track bullet mentions another track in prose

- **Type:** bug (ticketing tooling). Track T (owns tools/progress.py).
- **Opened:** 2026-07-15.

## Symptom

`Ticket.track()` detects R/T/O/E from the Type/Track declaration lines *before* it
reads the authoritative frontmatter `track:` field. So a ticket that says, in prose
inside its Type or Track bullet, "**Found by Track T's fuzzer**" or "compat (Track P —
...). Found by Track T (pasmith)" matches `\bTrack T\b` and is tagged **T** — even
with `track: A` (or P) in its frontmatter. The code comment already warns "detect
Track T ONLY in the declaration lines (never the body)", but a *mention* inside the
declaration line defeats it.

Three tickets hit this in one session (2026-07-15): the two pxx bugs filed by the
pasmith fuzzer (`bug-a-interface-release-*`, `bug-a-method-pointer-*`, meant for A)
and `compat-pascal-copy-of-char-literal` (meant for P) — all stranded under T, which
does not fix compiler/frontend bugs. Worked around by rewording each ticket, but the
next fuzzer finding that credits "Track T" will do it again.

## Fix (proposed)

Make the explicit frontmatter `track:` field win over prose mentions, while keeping
the slug-based R/O/E/T surfacing that intentionally overrides a `track: A`
file-ownership tag. Order in `track()`:

1. slug-based surfacing first (`feature-rust-` → R, `feature-opt-` → O,
   `feature-demo-`/`idea-demo-` → E, `feature-track-t-` → T) — these deliberately
   override an A file-owner tag;
2. **then the explicit `self.fm.get("track")` field** (normalized) — authoritative;
3. only then fall back to the decl-line `\bTrack X\b` regexes for tickets that
   declare their track in prose and set no field.

Alternatively, anchor the decl-line regex to the *start* of the bullet value (the
real declaration position) so a mid-sentence "Found by Track T" no longer matches.

## Acceptance

A ticket with `track: A` (or P/B/…) in frontmatter and a prose "Track T" mention in
its Type/Track bullet resolves to its frontmatter track; the existing R/O/E/T
slug-surfacing tickets are unchanged (add a couple as regression fixtures).

## Log
- 2026-07-15 — resolved, commit f39a071e.
