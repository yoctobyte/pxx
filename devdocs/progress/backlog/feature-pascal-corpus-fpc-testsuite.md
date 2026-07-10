---
prio: 60  # auto — rung 1 of the Pascal corpus; biggest dialect coverage per effort
---

# Pascal corpus rung 1 — FPC test-suite subset (conformance)

- **Type:** feature (frontend conformance corpus)
- **Track:** P (Pascal frontend)
- **Status:** backlog — filed 2026-07-10. Rung 1 of
  [[feature-pascal-corpus-expansion]].
- **Owner:** —

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
