# Track B library test suite

- **Type:** feature
- **Status:** done
- **Owner:** Codex
- **Opened:** 2026-06-20
- **Completed:** 2026-06-20
- **Relation:** Track B testing workflow; companion to
  `feature-parallel-tracks-stable-compiler`, `feature-platform-abstraction-layer`,
  and the demo/library backlog.

## Goal

Create a library-owned test path that is distinct from the compiler regression
suite. Compiler tests remain the Track A self-host/fixedpoint gate; library
tests run against `$(PXX_STABLE)` and can intentionally expose Track A or Track B
work requests without destabilizing the compiler gate.

## Delivered

- `tools/library_suite.sh` with three modes:
  - `green` - hard-fail curated library regressions.
  - `discovery` - non-gating probes that report `GAP` lines and Track A/B hints.
  - `all` - green plus discovery.
- Make targets (landed with the unit-search-path commit that touched the same
  Makefile block):
  - `make library-suite-green`
  - `make library-suite-discovery`
  - `make library-suite`
- Documentation in `devdocs/developer/library-testing.md` and
  `devdocs/dev/parallel-tracks.md`.
- Discovery probes for current known gaps:
  - chess -> missing `Exception` base class.
  - adventure -> missing text file IO (`Assign` etc.) on PAL.

## Acceptance

- `make library-suite-green` passes against pinned stable.
- `make library-suite` exits 0 while reporting known discovery `GAP` lines.
- Discovery gaps point to progress tickets instead of living only in terminal
  output.

## Log

- 2026-06-20 - Delivered in commit `d142dc2` (`test(lib): add Track B library
  suite`). Verified `make library-suite-green` and `make library-suite` against
  pinned v18. This ticket was created after the fact because the suite was
  implemented before a progress ticket existed; keep future harness/library
  features ticketed before or during implementation.
