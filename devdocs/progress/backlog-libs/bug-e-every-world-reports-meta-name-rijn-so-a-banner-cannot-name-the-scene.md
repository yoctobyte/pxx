---
slug: bug-e-every-world-reports-meta-name-rijn-so-a-banner-cannot-name-the-scene
track: E
prio: 60
type: bug
status: backlog
owner: ""
created: 2026-09-22
found-by: lekkerzeilen-7a (cost), reported by frankuser, verified by frankz-e5
tags: [lekkerzeilen, perf, measurement, name-is-not-the-thing]
blocked-by: []
summary: "`world/roofs` and `world/rijn` BOTH record `meta.name='rijn'` in their `index.lzi`, and the DIRECTORY never appears in any output -- so the banner prints `rijn` whichever scene is loaded and NO measurement can be attributed to a scene from its own log. Verified by query rather than relayed: `sqlite3 world/roofs/index.lzi \"select value from meta where key='name'\"` answers `rijn` with 4 rows in `tiles`; `world/rijn` answers `rijn` with 432. THE DISCRIMINATOR THAT WORKS TODAY IS TILE COUNT, 4 VERSUS 432. This is not cosmetic and it has a dated cost: it made 7a's harness reject six good runs over about an hour, and it puts a question mark on EVERY historical row labelled `rijn`, including the population line of `lekkerzeilen@devdocs/perf/PROFILE-2026-09-21.md`, on which all five edges of `umbrella-lekkerzeilen-runs-at-15-fps` were ranked. A label that is right for one scene and silently wrong for another is the 80%-accurate-name case: the part you sample confirms it. FIX IS TWO HALVES AND THE SECOND IS THE ONE THAT MATTERS -- (1) make the banner print something that cannot be shared, the world DIRECTORY, beside or instead of `meta.name`; (2) have every perf harness record the discriminating quantity (tile count) in its stamp, so an old log can be adjudicated rather than merely doubted. Retired when a run's own output identifies its scene without reference to any argument the operator remembers passing."
---

# Every world reports `meta.name='rijn'`

## Measured, not relayed

    sqlite3 world/roofs/index.lzi "select value from meta where key='name';"  ->  rijn
    sqlite3 world/roofs/index.lzi "select count(*) from tiles;"               ->    4
    sqlite3 world/rijn/index.lzi  "select value from meta where key='name';"  ->  rijn
    sqlite3 world/rijn/index.lzi  "select count(*) from tiles;"               ->  432

`/home/neo/lekkerzeilen`, 2026-09-22. There are twelve `world/*/index.lzi` in
that tree; only these two were checked, so **the population of affected worlds
is unmeasured** and "every world" in the title is the reported claim, not the
verified one. The verified claim is: **these two share a name, and the shared
name is the one every perf row cites.**

## Why it is worth a ticket rather than a one-line fix

**A banner that prints a name shared by two scenes is not a weaker label, it is
a false one** — it answers confidently and identically for a 4-tile scene and a
432-tile scene whose frame times differ by an order of magnitude. Nothing errors.

**The cost is already paid twice.** It refused six good runs of 7a's harness
over about an hour. And it means **no historical row labelled `rijn` can be
attributed to a scene from the log alone** — a reader must know whether the
operator passed `--region`, which is exactly the fact a log exists to preserve.

**The umbrella's whole lever list inherits that doubt.** All five edges of
`umbrella-lekkerzeilen-runs-at-15-fps` were ranked on
`PROFILE-2026-09-21.md`, whose population line says `--region rijn`.

## The fix, and the half that matters

1. Print the world **DIRECTORY**. It is unique by construction and no database
   field can drift away from it.
2. **Record the discriminating quantity in every perf stamp** — tile count will
   do. This is the half that pays: without it, fixing the banner makes future
   logs trustworthy and leaves every existing one permanently unadjudicable.

## What would retire this

A run whose own output identifies its scene **without reference to any argument
the operator remembers passing**, plus at least one historical row re-attributed
using the recorded discriminator rather than recollection.
