---
track: A
prio: 40
type: task
status: backlog
found: 2026-08-30
found-by: frankD
blocked-by: []
summary: "devdocs/developer/ is 83 .md files that CLAUDE.md and devdocs/dev/README.md both fail to name, so no lane owns it. 73 of 83 were last touched on 2026-06-26 by the commit that CREATED the tree, and that same commit broke citations inside it: 35 of 157 distinct cited paths do not resolve, including one that points at docs/historic/ for a file the split moved to devdocs/developer/historic/. Rationale is measured, not assumed: across the whole night's audit, doc accuracy tracked WHO IS ACCOUNTABLE for a page, not how many people read it -- docs/** (owned by D, fewer readers who could check it) was more accurate than devdocs/dev/** (heavily read, unowned)."
---

# `devdocs/developer/` is 83 unowned pages, 73 of them untouched since the day they were created

- **Type:** task (documentation audit) — the sweep, not the fixes
- **Track:** A — CLAUDE.md places the internal dev docs with A/B. Per-page
  findings route to whichever lane owns the *subject*; this ticket is the sweep.
- **Found:** 2026-08-30 by frankD, after auditing all 42 live `devdocs/dev/**`
  references and all 41 `docs/**` pages.

## Why this tree and not another — the rationale is a measurement

The night's audit produced one finding that says where to look next, and it
contradicts the assumption the fleet had been working under:

> **Accuracy tracked who is accountable for the page, not how many people read
> it.**

`docs/**` is owned by Track D, is published to the website, and has *fewer*
readers who could check it against the tree — and it was the **more accurate** of
the two sets. `devdocs/dev/**` is read by every agent every session and is owned
by nobody in particular, and it carried six superseded gate rules, four
completed-work-described-as-open claims on one page, and a dispatch model
describing worktrees that do not exist.

The many-eyes assumption predicts the opposite. Readership did not correct
errors; in the worst case it **preserved** them, because the stale rules were all
*tighter* than the rules that replaced them, so obeying one cost ten minutes and
produced nothing wrong. Nobody reports that.

So the next sweep should be ordered by **which pages nobody owns**, and
`devdocs/developer/` is the largest such surface in the repo.

## The measurement

| | |
| --- | --- |
| `.md` files | **83** — 36% more than `devdocs/dev/` (61), which has had a full pass |
| named in `CLAUDE.md` | **no** — the string `devdocs/developer` does not appear |
| named in `devdocs/dev/README.md` | **no** — that page classifies its own directory only |
| last touched 2026-06 | **73 of 83** |
| last touched 2026-07 | 6 |
| last touched 2026-08 | 4 |

CLAUDE.md names `docs/**` (D), `devdocs/dev/**` and `devdocs/progress/**`
(A/B). `devdocs/developer/**` is named nowhere, by either document that assigns
documentation ownership. **It is unowned by construction, not by neglect.**

### The citations broke in the commit that created the tree

Extracting every `compiler|lib|tools|test|docs/...` path mentioned across the 83
pages gives **157 distinct paths, of which 35 do not resolve**. Honest breakdown,
because the raw number overstates:

- **9** are pure `docs/` → `devdocs/` renames — the file is right there under the
  new prefix.
- **~3** are prose placeholders, not citations (`compiler/name.pas`,
  `compiler/name.c`, `compiler/name.h` in a "name your file" sentence). A path
  extractor cannot tell those from a real reference; a reader can.
- **~23 are genuinely stale**, including `compiler/parser.inc` (split into
  `pasparser_*.inc` on 2026-08-20), `docs/todo.md`, `docs/limitations.md`,
  `docs/pascal-dialect.md`, `lib/rtl/anybox.pas`, `lib/rtl/sqlitedb.pas`, and
  five `docs/progress/**` ticket paths whose tickets have since changed
  directory.

The sharpest one: `project-state.md` cites
`docs/historic/direct-codegen-legacy.inc`. That file exists — at
`devdocs/developer/historic/direct-codegen-legacy.inc`. **The commit that broke
the citation is the commit that created this tree** (`601c08105`, *"docs: split
public and internal docs"*, 2026-06-26), and in the 65 days since, nobody has
followed the link.

### A page whose heading asserts currency

`project-state.md` opens **"Project State Audit / Audited: 2026-06-12"** — 79
days ago — and its first architecture bullet reads:

> *"Pascal, C-subset, and BASIC-subset frontends share the native x86-64 Linux
> ELF emitter."*

Since then Nil Python became a **mainline** frontend with its own gate, Rust and
Zig arrived as experimental ones, and the emitter grew to six code-generating
targets. A reader taking that page at its word gets a 2026-06 project.

This is the same shape found twice already tonight — `Roles — LIVE`,
`## Current assignments`, a `## TODO` over five `done/` tickets. **A heading is
an assertion that nothing re-derives**, and `Audited: <date>` is the strongest
form of it, because it explicitly claims someone checked.

### Name collisions with the pages that ARE owned

`devdocs/developer/` contains `architecture.md`, `cli.md`, `compatibility.md`,
`c-interop.md`, `concurrency-memory-model.md`. `docs/reference/` contains
`architecture.md`, `cli.md`, and `status.md` covering compatibility.

Two files with one name, one owned and current, one unowned and two months
stale, is the `glossary.md` defect at directory scale: **two definitions of one
thing is not redundancy, it is a coin flip**, and the reader does not know they
tossed one.

## What this ticket asks for

**Not** "fix 83 pages". In order:

1. **Decide the tree's status** — this is the real question and it is a Track U
   call if A does not want it. Three options, and they are not equal:
   - *live reference* — then it needs an owner and a `README.md` classifying its
     files, the way `devdocs/dev/README.md` does. That page is the mechanism
     that made the 42-file sweep possible at all.
   - *historical record* — then say so at the top of each page and stop, because
     a record is not wrong for being old, and correcting one falsifies history.
   - *split* — most likely correct: `project-state.md` and `todo.md` want to be
     one or the other, and the `historic/` subdirectory shows the split was
     already begun.
2. **Then** sweep whatever remains classified as live. The tooling exists:
   `tools/docaudit.py` (`cites`, `slugs`, `limits`, `targets`, `comments`) is
   pointed at `devdocs/dev` and needs a directory argument, which is a small
   change and the cheapest part of this ticket.

## Prior art from the sweep that produced this

- `devdocs/dev/README.md` §4 — where that directory rots, and why a *command*
  attached to an obligation is necessary but not sufficient.
- The rot classes worth grepping for first, ranked by what they cost:
  superseded operating rules (all six found were **tighter** than current
  policy), finished work described as open, headings asserting currency, and
  dead ticket/file citations.

## Gate
None — audit and classification. Any code or library defect the sweep finds is
filed into the owning lane, never fixed under this ticket.
