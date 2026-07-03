# Fast pin: tiered test suite + stabilize-fast (target: pin in ~20s)

- **Type:** chore (build/test infrastructure) — Track A
- **Status:** backlog
- **Opened:** 2026-07-03

## Problem

Pinning a version today takes several minutes. Breakdown (2026-07-03, v162):

- `stabilize: test` — the FULL `make test` suite is a hard prerequisite
  (minutes: hundreds of compile+run+diff steps, qemu legs, dwarf smoke...).
- The fixedpoint chain itself is ~4 self-compiles x 10.4s ≈ 42s.
- `pin` is instant.

Regressions have been rare lately; the full gate is still valuable but does
not need to run on EVERY iteration pin.

## Plan

1. **`test-smoke`**: one curated aggregated regression program (or a small
   fixed set, <20s total) that packs the historically-regression-prone
   surfaces into single binaries: managed strings (COW/concat/refcount churn),
   dynarrays (SetLength/Copy/Insert/Delete incl. managed elements), records
   (managed fields, by-value args), classes (ctor/virtual/metaclass),
   sets, Int64 arithmetic, exceptions, write formatting, and a mini
   self-referential parser snippet. Assert-count style (`total ok N / N`)
   like test_dynarray_insert_delete. New features append cases here AND to
   their full-suite test.
2. **`stabilize-fast`**: same fixedpoint + byte-identity chain, but
   prerequisite = `test-smoke` instead of `test`. This is the everyday
   iteration pin. Full `stabilize` (full `test`) stays for milestone pins /
   before pushing a batch — policy note in parallel-tracks.md.
3. **Wall-time target**: 20s = fixedpoint chain (~42s today) + smoke. Needs
   the compile-speed work to land too:
   [[perf-compiler-hotspots-algorithmic]] (self-compile 10.4s -> ~7s) and
   [[feature-optimization-levels]] (2.04x codegen gap -> fixedpoint compiles
   ~2x faster again). With both, 4 x ~3.5s + smoke ≈ 20s. Also consider
   trimming the fixedpoint chain: gen2==gen3 byte-identity already proves the
   fixedpoint; s4/s5 re-derivations may be redundant (audit what each cmp
   actually guards before cutting).
4. Optional: `make test` parallelism (many recipe lines are independent
   compile+run pairs; `-j` unsafe today because of shared /tmp names —
   namespacing outputs would unlock it).

## Non-goals

Weakening the full gate: `make test` remains the bar for stabilize-before-
push-batch, releases, and anything touching codegen/ABI/ELF.

## Acceptance

`make stabilize-fast` green end-to-end in <=60s on the dev box today
(<=20s once the perf siblings land); policy documented; full `stabilize`
unchanged.
