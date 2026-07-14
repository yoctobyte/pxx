---
prio: 12  # RAINY-DAY (user call 2026-07-11): FPC-testsuite burndown deprioritized — own tests are the gate.
---

# FPC-conformance long tail: RTL gaps, runtime faults, small parser holes

- **Type:** task umbrella (catch-all for the audit's small clusters)
- **Track:** P (frontend) / B (RTL pieces)
- **Status:** backlog — filed 2026-07-10 from the FPC-testsuite audit
  ([[feature-pascal-corpus-fpc-testsuite]]).
- **Owner:** —

The four big clusters have their own tickets ([[bug-pascal-headerless-program]]
111, [[feature-pascal-delphi-generics-syntax]] 93+,
[[feature-pascal-generic-nonclass-templates]] 10,
[[feature-pascal-class-management-operators]] 8,
[[bug-pascal-missing-diagnostics-fail-tests]] 13). This ticket tracks the rest
(reasons verbatim in `test/pascal-conformance/pxx.skip`):

- **RTL gaps (B):** ~~`RandSeed`~~, ~~`flush`~~, ~~`strings` unit~~,
  ~~`RunError`~~, ~~`UniqueString`~~, ~~`HexStr`/`Lo`/`Hi`/`Swap`/`Erase`~~ —
  DONE 2026-07-14 (Track B burn: tset1/tstring7/tstring8/tarray8 greened,
  293 pass / 0 fail). Remaining: `ExitCode` (NOT a plain var — needs
  finalization execution + Halt semantics, split to
  [[feature-pascal-exitcode-finalization-halt]], Track A), `LowerCase`,
  `DynArraySize`/`DynArrayIndex`/`DynArraySetLength` (need dynarray TypeInfo
  RTTI), `IInterface`/`IEnumerator` base interfaces, `variants` unit, `fgl`
  unit, `TAB` const. tint642 re-triaged: blocked by
  [[bug-pascal-record-cast-field-offset]], not RTL.
- **Runtime faults (P/A, investigate first):** tforin3 + tstring1 segfault
  (139), tstring9 exit 2, tcase45_2/tcase46_2 exit 1, tarray11 exit 30,
  tover1 exit 1.
- **Parser small holes:** case-label edge cases (`case string label must not
  be empty`, `expected case label`, `case label must be constant`),
  `enumerator` modifier on class functions, `for-in` over custom enumerators,
  dynarray `+` concat (modeswitch arrayoperators), dynarray initializers,
  `declared(NAME)` conditional, operator overloading on plain types
  (`LongInt is not a record or class`), `Self` in class methods,
  static-field access paths, ConstEval `Pred` in const-expr,
  `Mismatch in MatchProcCall` (internal error — investigate).

## Method
Pick a sub-cluster, split it into its own narrowed ticket when starting real
work; burn skip-list entries as they green.
