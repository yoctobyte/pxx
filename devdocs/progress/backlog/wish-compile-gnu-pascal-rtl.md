# Wish: compile the GNU Pascal (GPC) runtime library under pxx

- **Type:** wish (compatibility stress test) — Track B
- **Status:** backlog
- **Opened:** 2026-06-30 (user: "rainy afternoon" / opportunistic, not planned work)
- **Relation:** same shape as [[feature-synapse-compile-check]] /
  [[feature-embed-pascal-script]] / [[feature-embed-dwscript-rtti]] — probe a
  real-world Pascal codebase under pxx, file Track A tickets for whatever
  breaks. Complements [[feature-mimic-fpc]] (FPC-identity compat) with a
  different dialect target: ISO 7185 / ISO 10206 Extended Pascal / Turbo
  Pascal, not FPC/Delphi.

## Correction on the literal ask (researched 2026-06-30)

"Compile the GNU Pascal Compiler" isn't quite the right target as stated:
**GPC's compiler itself is a GCC frontend written in C** (Wikipedia: "the
compiler is written in C... GNU Pascal is one notable exception, being
written in C, as most other Pascal compilers are self-hosting"). Compiling
that means compiling a slice of GCC's C codebase — out of scope, and a
Track C (cfront) concern if it were ever in scope at all, not this wish.

**GPC's runtime library, however, is mostly Pascal** — and it targets ISO
7185 (standard Pascal), implements most of ISO 10206 (Extended Pascal), and
has partial Turbo Pascal dialect support (per the GNU Pascal Manual). That's
a real, right-shaped, pxx-compatible target: a mature, standards-driven
Pascal codebase exercising a different dialect corner than FPC/Delphi-style
code (which is what most of pxx's compatibility work, e.g.
[[feature-mimic-fpc]], has focused on so far).

## Goal

Get pxx to compile (some meaningful slice of) GPC's Pascal-language runtime
library. Value: an ISO-standard-Pascal compatibility stress test, distinct
from the FPC/Delphi-flavored libraries pxx has mostly chewed on
(Synapse, Pascal Script, DWScript). Likely surfaces ISO 7185/10206-specific
constructs pxx hasn't seen yet (schema types, `goto` discipline, ISO file
handling — whatever GPC's RTL actually uses; **not verified yet, scope on
pickup**).

## Why this is a wish, not a real ticket yet

Nobody has looked at GPC's RTL source layout, license, or actual dialect
usage closely. Source is presumably at the GNU Pascal project (gnu-pascal.de
/ the `hebisch/gpc` mirror) — whoever picks this up should first locate the
RTL-specific subset (not the GCC-integration C code), get a feel for its
size/dialect before committing real time. This ticket is intentionally a
seed, not a scoped plan — same spirit as the rest of `backlog/`'s probe-style
tickets, just explicitly lower priority ("opportunistic / rainy-afternoon",
not queued work).

## Acceptance (loose, refine on pickup)

- A representative chunk of GPC's Pascal RTL source is identified and
  attempted under pxx (plain compile, no special mimic mode unless the
  source demands one).
- Real gaps found (missing dialect features, RTL surface, etc.) get filed as
  individual Track A/B tickets, same pattern as
  [[feature-synapse-compile-check]] — this ticket itself stays a tracking/
  seed entry, not a single big patch.

## Log
- 2026-06-30 — Opened as a wish (Track B). User raised whether the board
  needs dedicated organization for aspirational "wish" tickets; for now this
  uses the existing `backlog/` status with `**Type:** wish` as the marker —
  no new directory/tooling change, see chat note for the tradeoff.
