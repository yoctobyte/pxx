# C: granular `--system-libs` opt-out for the magic-link model

- **Type:** feature (C frontend → crtl link model) — Track C (+ A if reloc /
  DT_NEEDED emission touched)
- **Status:** backlog
- **Owner:** unassigned
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

## Notes / open questions

- Decide mapping header → soname stem (`<math.h>`→`m`, `<pthread.h>`→`pthread`).
- Mixed mode: ensure a symbol is not *both* magic-pulled and external
  (CrtlSrcPulled dedup already guards double-pull; external must win cleanly
  when its lib is named).
- Not urgent — sqlite path wants *everything* magic, so current coarse default
  already unblocks it. This is ergonomics for real-world mixed builds.
- See [[project_c_crtl_autopull_link_model]] for the link model and the
  `--system-libs` entry point; doc at
  `devdocs/dev/c-linking-and-crtl-autopull.md`.
