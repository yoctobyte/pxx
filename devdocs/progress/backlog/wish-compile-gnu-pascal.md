# Wish: compile the GNU Pascal project (GPC) under pxx — two angles

- **Type:** wish (compatibility stress test)
- **Track:** B+C
- **Status:** backlog
- **Opened:** 2026-06-30 (user: "rainy afternoon" / opportunistic, not planned work)
- **Relation:** Pascal-RTL angle is the same shape as
  [[feature-synapse-compile-check]] / [[feature-embed-pascal-script]] /
  [[feature-embed-dwscript-rtti]] (probe a real-world codebase, file Track
  A/C tickets for gaps); complements [[feature-mimic-fpc]] with a different
  dialect target (ISO 7185 / ISO 10206 / Turbo Pascal, not FPC/Delphi).
  C-frontend angle is a [[feature-c-source-frontend]] / `lib/crtl` stress
  test, in the spirit of `devdocs/developer/c-torture-candidates.md`'s
  real-world C probes.

## Two real targets, not one (corrected 2026-06-30, twice)

First pass wrongly dismissed "compile the GNU Pascal Compiler" outright:
GPC's compiler is a GCC frontend **written in C**, which I initially read as
"out of scope" — forgetting pxx **is also a C compiler** (Track C / cfront,
merged at v80). Both angles are real:

1. **GPC's runtime library (Pascal)** — ISO 7185 / ISO 10206 Extended
   Pascal, partial Turbo Pascal dialect support. A genuine pxx-Pascal-
   frontend stress test, dialect-different from the FPC/Delphi-flavored
   libraries pxx has mostly chewed on so far (Synapse, Pascal Script,
   DWScript).
2. **GPC's compiler frontend (C)** — the literal original ask, now back in
   scope via `cfront`/`lib/crtl`. **Honest risk flag, not verified yet:**
   GCC language frontends are typically deeply coupled to GCC's own internal
   headers/build machinery (`tree.h`-style internal types, GCC's macro/RTL
   infrastructure), not just standard C — this could make it a much heavier
   lift than the self-contained C codebases pxx has tested so far (SQLite,
   Lua, tiny-regex). Whoever picks this up should size that coupling first
   before assuming it's "just more C."

## Why this is a wish, not a scoped ticket

Nobody has looked at either GPC angle's actual source layout, license, or
real dependency depth yet. Source is presumably at the GNU Pascal project
(gnu-pascal.de) or the `hebisch/gpc` mirror. This ticket is a seed for
either/both angles — same spirit as the rest of `backlog/`'s probe-style
tickets, just explicitly lower priority ("opportunistic / rainy-afternoon").
Per the user: importance here is a "fuzzy indicator," adjust freely on
pickup rather than treating this as a fixed scope.

## Acceptance (loose, refine on pickup)

- Pascal-RTL angle: a representative chunk of GPC's Pascal RTL compiles
  under pxx (plain compile, no special mimic mode unless the source demands
  one).
- C-frontend angle: GCC-coupling depth assessed first; if a self-contained-
  enough slice exists, attempt it under `cfront`; if not, document why and
  park it rather than forcing it.
- Either angle: real gaps found get filed as individual Track A/B/C tickets,
  same pattern as [[feature-synapse-compile-check]] — this ticket stays a
  tracking/seed entry, not a single big patch.

## Log
- 2026-06-30 — Opened as a wish (Track B), scoped to the Pascal RTL only —
  C-frontend angle wrongly ruled out as "out of scope."
- 2026-06-30 — Corrected: pxx is also a C compiler (Track C/cfront), so the
  original literal ask (GPC's C-language compiler frontend) is back in
  scope as a second angle, alongside the Pascal RTL. Retitled, rescoped to
  Track B+C. User noted importance here is a fuzzy/adjustable indicator, not
  a hard priority.
