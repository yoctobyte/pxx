---
prio: 48  # auto — 8 conformance tests
---

# `class operator` + named operators (Initialize/Finalize/Explicit/...)

- **Type:** feature (Pascal frontend, operator overloading)
- **Track:** P (shared `parser.inc` — A-gated)
- **Status:** backlog — filed 2026-07-10 from the FPC-testsuite audit
  ([[feature-pascal-corpus-fpc-testsuite]]).
- **Owner:** —

## Symptom
`error: expected operator symbol after operator keyword` — pxx parses only
symbol operators (`operator +` etc.). Missing:
- **management operators** in advanced records: `class operator
  Initialize/Finalize/AddRef/Copy(var a: TFoo)` (tmoperator*) — these have
  *semantics* (compiler-invoked at var lifetime events), not just parse;
- named conversion/logic operators FPC accepts (`Explicit`, `:=`
  assignment-operator spelling, `in`, `inc`, `dec`).

## Impact
8 curated failures (`tmoperator*`, `tassignmentoperator1`, some `toperator*`).
Skip-list reason: `parser: named/class operator`.

## Note
Parse-side is P; the lifetime-event *invocation* (Initialize on entry,
Finalize on scope exit) likely needs IR/lowering support → that part is a
Track A ticket when reached.

## Gate
`make test` + self-host byte-identical; burn the skip-list entries.
