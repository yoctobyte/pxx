---
prio: 55
---

# Pascal corpus: fpcunit — OOP + RTTI test framework (and the harness for the rest)

- **Type:** feature (Pascal frontend validation)
- **Track:** P — tag: compat
- **Status:** backlog — opened 2026-07-12.
- **Owner:** —
- **Parent:** [[feature-pascal-corpus-oop]]
- **Unblocks:** [[feature-pascal-corpus-passrc]] (its tests are fpcunit-based), and every
  other FPC library whose suite is written against fpcunit.

## Why
Two payoffs in one:
1. **It is OOP by construction** — `TTestCase` inheritance, `TTestSuite` composite,
   `ITestListener` / `ITestResult` interfaces, exception classes, and — the interesting
   part — **published-method enumeration via RTTI** to discover `Test*` methods. That RTTI
   path is exactly the surface self-host never touches.
2. **It is the harness.** Nearly every FPC library ships its tests as fpcunit suites. Land
   fpcunit and the marginal cost of the next library drops to "vendor + run".

## Shape (verify at vendor time, do not re-derive from memory)
- Lives in FPC tree: `packages/fcl-fpcunit/src/` — `fpcunit.pp`, `testregistry.pas`,
  `testreport.pas`, `testdecorator.pp`, `ubmockobject.pp`, plus console/XML/plain runners
  (`consoletestrunner.pas`, `xmlreporter.pas`). Non-GUI runners only — ignore the GUI ones.
- Local checkouts already present: `/usr/share/fpcsrc/3.2.2/packages/` and
  `/home/rene/src/fpc-source/packages/`.
- Its own tests: `packages/fcl-fpcunit/tests/` (self-testing framework).

## Plan
1. Vendor pinned fcl-fpcunit source via `tools/install_lib_candidates.sh` (PROVENANCE.md
   with the FPC tag/commit). Keep it read-only vendor; do not fork.
2. Compile `fpcunit.pp` + `testregistry` + `consoletestrunner` with `$(PXX_STABLE)`. Expect
   the first wall around **RTTI published-method lookup** (`GetMethodName` / `MethodAddress`
   / `TypeInfo` on classes) and possibly `TStringList`/`TFPList` breadth in the RTL.
3. `make test-fpcunit`: build and run the framework's OWN suite, plus a hand-written
   ~10-case suite of ours (asserts pass/fail/error/ignore, setup/teardown ordering,
   nested suites, exception expectation).
4. Each failure → minimal repro vs FPC → fix ONE in the owning lane → `bXXX` regression.

## Acceptance
`make test-fpcunit` green: framework compiles, self-discovers test methods by RTTI, runs a
suite, and the console runner's summary matches FPC's for the same suite.

## Gate
Frontend/IR changed → `make test` + self-host byte-identical → `make stabilize && make pin`.
Cross where a backend/runtime is touched.

## Log
- 2026-07-12 — opened, split out of [[feature-pascal-corpus-oop]].
