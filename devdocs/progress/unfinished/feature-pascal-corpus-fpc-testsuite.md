---
prio: 60  # auto — rung 1 of the Pascal corpus; biggest dialect coverage per effort
---

# Pascal corpus rung 1 — FPC test-suite subset (conformance)

- **Type:** feature (frontend conformance corpus)
- **Track:** P (Pascal frontend)
- **Status:** working
  [[feature-pascal-corpus-expansion]].
- **Owner:** fable-ebp

## Idea
FPC ships `tests/test/**` — thousands of small `.pp` programs, each exercising
one language feature (`tbs*`, `tobject*`, `tgeneric*`, `terror*` for expected
failures, etc.). It is the **c-testsuite analog for Pascal**, but authoritative
(the reference compiler's own suite) and far larger. PXX is FPC-faithful, so most
should compile + run to the same result — and every one that doesn't is a sharply
localized dialect bug.

## Scope (start small, ladder up)
- Vendor a **curated subset** first (installer fetcher, pinned FPC release tag,
  gitignored) — not all thousands at once. Begin with the categories the compiler
  self-host never exercises: **generics** (`tgeneric*`), **classes/properties/
  visibility** (`tobject*`, `class*`), **exceptions** (`texcept*`), **RTL/string/
  math** units, **operator overloading**, **variants**.
- Runner (mirror `install_lib_candidates.sh` + the c-testsuite harness): compile
  each, run, diff stdout; honor the suite's `%FAIL`/`%NORUN`/expected-error
  markers so `terror*` negatives count as pass when they correctly reject.
- **Skip list, burned ticket by ticket** — same discipline as c-testsuite: a
  failing program → one narrowed frontend bug (Track P for `lexer`/`parser`/
  dialect, Track A for IR/backend). Do NOT inline-fix during the audit; file, then
  resolve. Report the running pass count (like c-testsuite 220/220).

## Watch-outs
- FPC test suite assumes FPC RTL + modes; gate each program on **mode** and unit
  availability — a test needing a unit PXX lacks is a skip (→ RTL/library ticket),
  not a frontend bug. Separate "dialect gap" from "missing RTL."
- Expected-failure tests (`terror*`) must be run for *rejection*, not acceptance
  — a PXX that accepts an invalid program is a real bug the suite catches.
- Keep the vendored tree gitignored; commit only the fetcher + the skip-list +
  pass-count report.

## Gate
`make test` + self-host byte-identical for any frontend fix (shared
`lexer.inc`/`parser.inc`). Rung is "green" at an agreed pass threshold on the
curated subset; expand the subset as rungs clear.

## Links
Rung of [[feature-pascal-corpus-expansion]] · method mirror
[[feature-c-corpus-expansion]] · dialect policy
[[project_fpc_compat_next_queue]] · [[project_mimic_fpc_done]].

## 2026-07-10 — infra landed + baseline audit

- Fetcher: `tools/install_lib_candidates.sh fpc-testsuite` — sparse
  `tests/test` + `tests/tstunits` (erroru et al, symlinked next to the tests)
  at FPC `release_3_2_2` (0d122c49), gitignored, PROVENANCE.md.
- Runner: `tools/run_pascal_conformance.sh` — curated categories (generics,
  classes/props, exceptions, operators, strings/arrays/sets/case/enums/for-in,
  extended records, interfaces...), FPC dotest directives honored (`%FAIL` =
  must-reject, `%NORUN`, `%RESULT`, cpu/target/version/opt gates auto-skip),
  `--shard I/N`, `--all`, `--only GLOB`. Skip list
  `test/pascal-conformance/pxx.skip` (name + reason), same discipline as
  c-testsuite.
- **Baseline: 222 pass / 294 skip-listed / 34 auto-gated of 550 curated.**
- Cluster tickets filed: [[bug-pascal-headerless-program]] (111!),
  [[feature-pascal-delphi-generics-syntax]] (93),
  [[feature-pascal-generic-nonclass-templates]] (10),
  [[feature-pascal-class-management-operators]] (8),
  [[bug-pascal-missing-diagnostics-fail-tests]] (13),
  [[task-pascal-conformance-long-tail]] (rest).
- Note: the two big parser clusters touch shared `parser.inc` → sole-A
  confirmation needed before an E+B+P agent edits them.

## Parked 2026-07-10
Infra + baseline + cluster tickets landed (see above). Burn-down of the two big
parser clusters edits shared `parser.inc` — needs the sole-A confirmation an
E+B+P agent doesn't have. Resume: grab a cluster ticket, confirm sole-A, burn
skip-list entries.
