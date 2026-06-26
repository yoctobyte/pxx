# Parallel tracks: pin libraries/demos to a "stable" compiler

- **Type:** feature
- **Status:** done
- **Owner:** —
- **Opened:** 2026-06-19
- **Resolved:** 2026-06-19

## Goal

Let compiler work (track A) and library/demo work (track B) proceed in parallel
without stepping on each other. The synchronisation boundary is a **stable
compiler binary**: B compiles libraries and demo apps with a frozen, git-tracked
`pascal26` (`stable_linux_amd64/default/latest`) instead of the in-flux
`compiler/pascal26`, so A can rebuild/regress the compiler freely while B keeps
working against a known-good baseline. Current platform (x86-64) only;
cross-compile is a later concern (assumed working on stable; the cross suites
discover any gaps later).

## Why now

The stabilize machinery already exists (`make stabilize` / `check-stable` /
`revert`, versioned binaries under `stable_linux_amd64/`), but:
- the recorded stable is **v8 (2026-05-29)** — ~3 weeks and hundreds of procs
  behind HEAD; it cannot even compile the current examples, and
- **nothing uses it**: every lib/demo build runs against `$(COMPILER)`, so
  library work is coupled to compiler churn.

## Design

- **Boundary = the stable binary.** `PXX_STABLE ?= stable_linux_amd64/default/latest`.
  Track B targets compile with `$(PXX_STABLE)`; an env override
  (`PXX_STABLE=stable_linux_amd64/default/vN`) pins a specific version when
  chasing a regression. B auto-follows `latest` by default.
- **Publishing a new stable** (track A, when a feature B needs lands): `make
  stabilize` runs the authoritative gate (`make test` + 4-iteration fixedpoint),
  bumps the version, and records the binary + sha + `history.log` line
  (timestamp, vN, sha, commit hash, commit subject). `history.log` is the
  changelog/sync point. Commit the new `stable_linux_amd64/**` artifacts.
- **Lanes are soft guidelines, not walls.** Ideal split: A owns `compiler/**`
  and compiler/cross/esp/bootstrap tests; B owns `lib/**`, `examples/**`, new
  `test/lib_*`, and the `lib-test`/`demos` Makefile block. But this is a
  *dialect* — A is free to touch libraries when a test or builtin needs it, and
  B may be asked to bug-hunt/advise. Grey zone is expected; the doc states the
  ideal, it does not enforce it.
- **lib-test is NOT authoritative.** The authoritative gate stays self-host
  compile + `make test`; features must not fail that. `lib-test` is a discovery
  / smoke harness for B. `demos` is a compile-smoke dashboard (exit 0, prints a
  per-app status table). When either surfaces missing/bugged library or language
  support, **file a ticket** — don't treat the red as a hard gate.

## Deliverables

1. Refresh stable to current HEAD (`make stabilize` → v9). Unblocks B.
2. `PXX_STABLE` var + a staleness note in `lib-test` (recorded stable commit vs
   HEAD).
3. `make lib-test` — curated green subset against `$(PXX_STABLE)` (sudoku output
   check + lib/rtl smoke: collections, math). May hard-fail (smoke gate for B).
4. `make demos` — compile-smoke every `examples/*` app against `$(PXX_STABLE)`;
   prints OK/FAIL table, exit 0 (dashboard, not a gate).
5. `devdocs/dev/parallel-tracks.md` — the A/B protocol.
6. File discovery tickets for the example breakages found while wiring this up
   (primes `IntToStr`, adventure `Copy`, chess parse error) — demonstrates the
   discovery→ticket loop.

## Acceptance

`make stabilize` records a current-HEAD stable; `make lib-test` passes against
it; `make demos` prints a status table; the protocol doc exists; `make test`
and self-host fixedpoint stay green.

## Log
- 2026-06-19 — opened and implementing immediately (user request to set up
  parallel compiler/library tracks).
- 2026-06-19 — done. `PXX_STABLE` var + `pxx-stable-check` / `lib-test` /
  `demos` targets landed; `devdocs/dev/parallel-tracks.md` written; stable
  refreshed v8 → v9 at current HEAD. `lib-test` green (sudoku exact +
  collections + math); `demos` dashboard runs. The dashboard immediately
  surfaced three real gaps, filed as discovery tickets:
  `lib-intToStr-missing`, `lib-string-copy-trim-missing`,
  `bug-const-expr-shl-shr-not-folded`. Resolved.
