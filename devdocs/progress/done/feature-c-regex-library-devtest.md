# C regex library dev-test import

- **Type:** feature (C frontend / RTL candidate)
- **Status:** done
- **Closed 2026-06-29:** acceptance met by the tiny-regex backend. The old
  `re_matchp` undefined-variable compiler gap is resolved; `re.c` compiles and
  runs. Added a real drop-in driver `test/crtl_tiny_regex_match.c` (unity-includes
  `re.c`, asserts known POSIX cases `[0-9]+ / ^hello / \w+@\w+ / a.c`), wired into
  `make` (expects `tiny-regex: all cases pass`) and pointed the
  `c_interop_devtest.sh` dashboard at it (`tiny_regex_re` now `OK`). License:
  kokke/tiny-regex-c is public domain; drop-in, no edits. The *preferred full
  POSIX (FreeBSD/Henry-Spencer) backend* remains an optional future stretch, not
  a blocker for this ticket's acceptance ("the selected C regex source").
- **Track:** C (C frontend)
- **Owner:** —
- **Opened:** 2026-06-20
- **Relation:** exercises `feature-c-source-frontend`; eventual destination is
  `lib/crtl/` or `lib/rtl/`, but only after the source compiles cleanly.

## Goal

Use a real C regex implementation as a candidate library workload for the C
frontend and as a future compiler-owned regex library. Start under
`library_candidates/`, not under `lib/`, because the source is expected to
surface many missing C-body features before it is usable.

Preferred full backend: a BSD libc / Henry Spencer lineage POSIX regex
implementation (`regcomp`, `regexec`, `regerror`, `regfree`). This is a better
fit than depending on PCRE or the host libc: it is real regex, permissively
licensed, portable, and suitable for embedded targets once PXX can compile it.

## Policy

- **Staging first:** keep imported source in `library_candidates/regex-*` until
  it compiles and has tests.
- **Drop-in preferred:** avoid editing upstream source where possible, so this
  remains a strong C-frontend proof.
- **Edits allowed:** because this is intended to become a stable owned library,
  small local source edits are acceptable if macro soup, libc assumptions, or
  portability glue block progress. Record every edit and why.
- **Multiple regex backends are allowed:** a full POSIX backend and a tiny
  embedded backend can coexist, with user choice by unit/profile. The same
  principle applies to other library families where different targets need
  different tradeoffs.

## Expected compiler pressure

- C expression precedence and pointer arithmetic
- local/global structs and arrays
- loops, `switch`, `break`, `continue`
- internal headers and object-like / function-like macros
- `malloc`/`free` or allocator replacement hooks
- `ctype`/string helper assumptions
- conditional compilation and portability defines

## Acceptance

- The selected C regex source compiles from the dev-test directory with PXX.
- A small C or Pascal-facing test validates known POSIX regex cases.
- License provenance and any local edits are documented.
- Only then move the selected backend into `lib/crtl/` or `lib/rtl/`.

## Log
- 2026-06-20 — Opened from discussion: use regex as a real C-source library
  milestone, stage outside `lib/`, prefer drop-in but allow targeted edits, and
  keep the design open to multiple regex implementations.
- 2026-06-20 — Candidate snapshots imported:
  `library_candidates/freebsd-regex/` from FreeBSD `freebsd-src`
  `22d66952555c86a5b7d1d499b48906c3a5f4c13d`, and
  `library_candidates/tiny-regex-c/` from `kokke/tiny-regex-c`
  `f2632c6d9ed25272987471cdb8b70395c2460bdb`. No local source edits at import.
- 2026-06-20 — Added non-gating `make c-interop-devtest` probes for the
  candidates against pinned v17 and the new `lib/crtl/include` root. Current
  dashboard: `crtl_header_smoke` OK, `tiny_regex_header` OK,
  `freebsd_regex_header` OK, `tiny_regex_re` GAP
  (`pascal26:160: error: undefined variable (re_matchp)`). That gap maps to the
  existing `feature-c-source-frontend` multi-function/body slice rather than a
  regex source edit.
