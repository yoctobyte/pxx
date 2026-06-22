# bochan + eduth — headless test driver + validator for garin

- **Type:** feature (app / test infra)
- **Status:** working
- **Track:** B
- **Parent:** feature-eliah-ide
- **Owner:** Track B agent
- **Opened:** 2026-06-22

## Goal

A CLI testing interface for the shared core (garin), with NO GUI/TUI face linked
— proves garin is render-agnostic (compiles without `lib/pcl`).

- **bochan** (בוחן, "examiner") — active driver. Exercises garin headless, emits
  results, exits nonzero on failure.
- **eduth** (עדות, "testimony") — validator unit. Witnesses results, asserts vs
  expected truth, tallies pass/fail, returns the verdict / exit code.

bochan drives; eduth judges.

## Scope

- `apps/ide/eduth/eduth.pas` — assertion API: `CheckTrue/CheckInt/CheckStr`,
  pass/fail tally, `EduthReport` → exit code. Golden = inline for now; golden
  files later.
- `apps/ide/bochan/main.pas` — scenarios over `garin/buffer.pas` (load known
  file → line count + content; missing file → false + reset). More as garin grows
  (project, docmodel, builder).
- `apps/ide/bochan/fixtures/` — test inputs.
- `apps/ide/test.sh` — build (`$(PXX_STABLE)`, only `-Fu` garin/eduth/rtl, **no
  pcl**) + run; exit code = gate.

## Acceptance

`apps/ide/test.sh` builds bochan WITHOUT lib/pcl and runs green (eduth reports 0
failures). Any compiler gap → Track A ticket, no workaround.

## Log
- 2026-06-22 — opened + taken.
- 2026-06-22 — DONE. `eduth/eduth.pas` (TEduth + CheckTrue/Int/Str + EduthReport
  exit code), `bochan/main.pas` (6 garin buffer scenarios), `bochan/fixtures/
  three.txt`, `apps/ide/test.sh`. Builds with `$(PXX_STABLE)` using ONLY
  `-Fu lib/rtl/garin/eduth` (no lib/pcl) → garin proven render-agnostic. Run:
  6 passed / 0 failed, exit 0. Zero workarounds, no compiler ticket.
