# C: granular `--system-libs` opt-out for the magic-link model

- **Type:** feature (C frontend → crtl link model) — Track C (+ A if reloc /
  DT_NEEDED emission touched)
- **Status:** done
- **Owner:** Track C+A
- **Found / Opened:** 2026-06-28, follow-up to the magic-link landing
  (763f04cc, [[project_c_crtl_autopull_link_model]]).

## Context — the agreed model

The C frontend has **no link step**. Default is the "magic link": a crtl
`#include <header>` auto-pulls its sibling impl `lib/crtl/src/<name>.c`
(e.g. `<math.h>` → `math.c` → fabs/sqrt/… bind case-insensitively to the
Pascal RTL), so a program links **libc-free, zero DT_NEEDED**. This is what
lets sqlite (whose own Makefile would normally link libc/libm *after* the
compile) just build and run with nothing external.

We decided: **magic link stays the default.** The programmer opts out *only*
when they explicitly want the real system library. Today that opt-out exists
but is **all-or-nothing**: `--system-libs` (compiler.pas:134) flips the *whole*
crtl namespace to real external `.so` resolution (DT_NEEDED libc, libm, …).

## The gap

All-or-nothing is too coarse for the realistic case "I want the magic crtl for
everything **except** libm (give me the real `libm.so`)", or vice-versa. A
programmer stating "use external libm" should not lose the libc-free magic for
string/stdio/etc.

## Proposed

Per-library opt-out, e.g. `--system-libs=m,pthread` (comma list of soname
stems) → only those headers resolve to a real `.so` (emit DT_NEEDED), the rest
stay magic-linked. Bare `--system-libs` keeps current meaning (everything
external) for back-compat. Likely also a source-level form (pragma / directive)
so the choice travels with the code, mirroring `{$MIMIC FPC}` etc.

Policy:

- If PXX ships a credible crtl implementation for a standard C library/header,
  the default is project-owned and libc-free. The programmer may override it
  explicitly with `--system-libs=<stem>` or the future source-level equivalent.
- If PXX cannot realistically emulate a library (GTK, OpenGL, system vendor
  SDKs, database/client libraries beyond a small compatibility shim), external is
  the default: declarations should bind to the real shared library / soname
  profile instead of pretending there is a bundled implementation.
- A mixed program is normal: e.g. magic `string`/`stdio`, real `m`, real `gtk`.
  The resolver must make that composition explicit and avoid accidental global
  flips.

## Notes / open questions

- Decide mapping header → soname stem (`<math.h>`→`m`, `<pthread.h>`→`pthread`).
- Define the bundled-vs-external registry in one place: header/module name,
  default provider (`crtl` or `system`), soname stem, and optional versioned
  soname mapping. This keeps GTK-style libraries external by default while
  preserving magic crtl for libc-compatible headers.
- Mixed mode: ensure a symbol is not *both* magic-pulled and external
  (CrtlSrcPulled dedup already guards double-pull; external must win cleanly
  when its lib is named).
- Not urgent — sqlite path wants *everything* magic, so current coarse default
  already unblocks it. This is ergonomics for real-world mixed builds.
- See [[project_c_crtl_autopull_link_model]] for the link model and the
  `--system-libs` entry point; doc at
  `devdocs/dev/c-linking-and-crtl-autopull.md`.

## Resolution

Implemented 2026-06-28.

- Bare `--system-libs` keeps the old all-external behavior.
- `--system-libs=<comma-list>` now records selected soname stems. A selected crtl
  header skips bundled auto-pull and its declarations route to real system
  externs; unselected crtl headers stay magic-linked.
- Header/module-to-soname rules now live in one registry helper used by Pascal
  C-header imports, C crtl auto-pull, and C external selection. Non-emulated
  integration libraries such as GTK/zlib/sqlite/pthread/dl are modeled as system
  libraries by default.
- Exact case-sensitive C symbols now win over case-insensitive Pascal fallback in
  C programs. This is required for `--system-libs=m`, because `pxxcio` loads the
  Pascal math unit before the C source is parsed.
- C-header `CurrentCLibrary` is scoped to the imported header so nested imports
  such as `math_ext.h` do not leak their soname into later C parsing.

Tests:

- `test/csystem_libs_granular_math_b112.c`: `--system-libs=m` runs successfully,
  emits direct `DT_NEEDED libm.so.6`, and keeps libc out of direct dependencies.
- `test/csystem_libs_granular_libc_b113.c`: `--system-libs=c` emits direct
  `DT_NEEDED libc.so.6` while keeping math on the bundled path (`no libm.so.6`).
  This is structural only because the pre-existing whole-program C libc external
  runtime path still has call/runtime gaps independent of this ticket.
- `make test` passed.
