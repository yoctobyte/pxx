---
prio: 60  # auto
---

# Game and engine library candidate suite

- **Type:** feature / investigation (library-suite discovery + compiler test workloads)
- **Status:** working
- **Track:** B+C
- **Owner:** opus-night
- **Opened:** 2026-06-28
- **Relation:** expands [[feature-c-source-frontend]], [[feature-c-regex-library-devtest]], [[feature-synapse-compile-check]], and [[feature-embed-pascal-script]] with game/engine-shaped workloads. Candidate catalog: [[game-library-candidates]].

## Goal

Pull in more real libraries as non-gating compiler testing ground, focused on
game engines/frameworks and their low-level support libraries. The intent is not
to ship these as dependencies by default; the first value is discovery pressure
for the compiler, C frontend, RTL, PAL, and FPC/Delphi compatibility surface.

## Candidate set

Use `devdocs/developer/game-library-candidates.md` as the ranked source list.
First wave:

- Pascal: New-ZenGL, Apus Game Engine, Castle Game Engine.
- C: stb, cglm, miniaudio, ENet, Nuklear, sokol, raylib, Orx.

Defer SDL, Allegro, TIC-80, Doom/Quake/Build-family engines, and legacy
Delphi/DirectX engines until the smaller candidates have produced useful gaps.

## Policy

- Stage in `library_candidates/<name>/`, not `lib/`.
- Prefer pinned upstream commits or release archives. Record URL, commit/tag,
  date imported, license, and any local edits.
- Keep discovery non-gating unless a small slice graduates into an owned library
  smoke.
- Do not patch around compiler failures silently. Classify each gap:
  - Track A: Pascal language, codegen, ABI, parser, or compiler bug.
  - Track B: RTL/PAL/library surface, Pascal compatibility units, examples.
  - Track C: C header/source frontend, C preprocessor, CRTL.
- GPL/copyleft candidates are allowed only as local discovery workloads unless a
  separate license decision says otherwise.

## Slices

### A - import metadata and harness shape

Add a tiny manifest convention for `library_candidates/` imports, or reuse the
existing candidate pattern if one has emerged. The manifest should capture
upstream URL, pinned revision, license, import date, local patches, and the
current first failing probe.

Acceptance: one candidate import has a manifest plus a `make` or script entry
that can run the probe without affecting `make test`.

### B - first C ladder

Import and probe in this order: stb, cglm, miniaudio, ENet, Nuklear, sokol. Keep
each first probe intentionally small. The expected early win is a good map of
C-body, macro, struct, callback, enum, and standard-library gaps.

Acceptance: each imported candidate has either one passing header/import probe or
a documented first compiler gap mapped to an existing/new ticket.

### C - first Pascal ladder

Probe New-ZenGL first, then Apus, then a deliberately tiny Castle Game Engine
slice. Keep the editor/build-tool surfaces out of scope until core units compile.

Acceptance: each Pascal candidate has a recorded first blocker list, with genuine
compiler gaps split out and RTL/PAL/library gaps kept here or in Track B tickets.

### D - graduate useful slices

When a candidate slice compiles cleanly and has a deterministic smoke, decide
whether it stays discovery-only or graduates:

- `lib/crtl/` for C runtime-style support libraries.
- `lib/rtl/` for owned Pascal library surfaces.
- `examples/` for demos that prove the compiler in public.
- `library-suite-discovery` for ongoing non-gating coverage.

Acceptance: at least one candidate slice graduates to a stable smoke or is
explicitly recorded as discovery-only with the reason.

## Done when

At least three candidates from different shapes have been imported and probed:
one single-header C library, one nontrivial C source library, and one Pascal game
library/engine. Their first blockers are either fixed or filed as focused
tickets, and the discovery command reports their status without breaking the
green library suite.

## Log

- 2026-06-28 — opened from the game-engine candidate discussion. Added ranked
  catalog in `devdocs/developer/game-library-candidates.md`; intent is to use
  suggestions as testing ground and extract only the source-compilation-relevant
  candidates.

- 2026-07-08 (fable-c, C ladder / slice B) — imported stb, cglm, ENet
  (installer fetchers `stb`/`cglm`/`enet`, pinned commits, gitignored). First
  probes under `test/gamelib/`, each mapping a first compiler/runtime gap:
  - **stb** (stb_sprintf.h) → inline fn-pointer PARAM call not registered:
    [[bug-c-inline-fnptr-param-call]].
  - **cglm** → (1) crtl lacked the C99 float-math family (added fabsf/sqrtf/...
    then REVERTED on discovering (2)) float-returning C functions return 0:
    [[bug-c-float-single-return-zero]]; and local nested aggregate initializers
    fail: [[bug-c-local-nested-aggregate-init]].
  - **ENet** → crtl missing `<netinet/tcp.h>`/`<netdb.h>`/`<poll.h>`
    ([[bug-c-crtl-missing-net-headers-enet]]) → host-header fallback redefines
    `struct in_addr` and trips a struct-tag-redefinition field-misfile that
    makes a record self-referential → compiler SIGSEGV
    ([[bug-c-tag-redef-misfiles-field-selfref-segv]]).
  Landed in-lane and green: crtl `arpa/inet.h` IPv4 text conversion
  (inet_aton/inet_addr/inet_pton/inet_ntop — ENet's actual needs, all
  pointer-based) + `test/gamelib/crtl_inet_smoke.c` in test-core. inet_ntoa
  (4-byte struct BY VALUE) omitted — hits a small-struct-byval param gap, not
  needed by ENet. Slice B acceptance (each candidate: passing probe OR filed
  gap) met for the three C candidates. Pascal ladder (slice C) unstarted —
  Track B.
- 2026-07-11 (ticket maintenance) — re-merged the orphaned log fragment that
  had landed on the backlog path while the full ticket sat parked in
  unfinished/ (duplicate file). Slice B (C candidates: stb/cglm/ENet probed,
  gaps filed) DONE; slice C (Pascal ladder) unstarted — Track B.
- 2026-07-11 (opus-night, Pascal ladder / slice C started) — imported
  **New-ZenGL** (installer fetcher `zengl`, pinned commit 26f40251, gitignored)
  and probed the leaf units (`test/gamelib/zengl_probe1.pas`). Three Track P
  blockers filed, in order of encounter:
  - **[[bug-pascal-high-low-in-const-expr]]** — `array[0..High(LongWord) shr
    1 - 1]` (zgl_types.pas:105) rejected by the const evaluator; even
    `array[0..High(Byte)]` fails. Local-patched in the candidate tree
    (literal bounds + marker comments) to keep probing; zgl_types then
    compiles clean.
  - **[[bug-pascal-directive-inside-paren-star-comment]]** — zgl_gltypeconst
    has a big `(* ... *)`-commented block of half-translated C `#if` junk
    (`&&`, `{$include <inttypes.h>}`); PXX evaluates `{$...}` inside `(* *)`
    comments and dies. FPC treats them as comment text. Hard-blocks every
    unit that pulls zgl_gltypeconst (i.e. nearly all of ZenGL).
  - **[[bug-pascal-include-search-silent-miss]]** — `{$I zgl_config.cfg}`
    lives in `headers/` while units live in `src/`/`srcGL/`; PXX has no
    `-Fi` include path AND a missing include is silently dropped, so every
    zgl unit compiles with the wrong (empty) configuration. The silent miss
    is the dangerous half.
  Probe checked in (documents the fetch/compile line + blocker list); ladder
  parked until the lexer-level P tickets land — next Pascal candidate (Apus)
  will likely hit the same include-path wall, so fixing these first is the
  cheaper path.
