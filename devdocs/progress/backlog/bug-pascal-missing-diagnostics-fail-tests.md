---
prio: 46  # auto — 13 %FAIL conformance tests accepted; each is a missing check
---

# pxx accepts invalid programs the FPC suite's %FAIL tests reject

- **Type:** bug umbrella (Pascal frontend, missing diagnostics)
- **Track:** P
- **Status:** backlog — filed 2026-07-10 from the FPC-testsuite audit
  ([[feature-pascal-corpus-fpc-testsuite]]).
- **Owner:** —

## Symptom
13 curated `{ %FAIL }` tests — programs the reference compiler must REJECT —
compile cleanly under pxx. Each is a missing semantic check. Skip-list reason:
`accepts-invalid`. Current list (audit 2026-07-10):

tarrconstr8 tdefault2 tdefault4 tdefault6 tdefault12 tenum4 terecs9 terecs12c
terecs13c tforin11 tgenconstraint38 tgenconstraint39 tgeneric56

Read each test's header comment for what diagnostic is expected (e.g. Default()
on forbidden types, extended-record visibility violations, generic-constraint
violations, invalid array constructors, for-in over non-iterable).

## Method
One test at a time: reproduce → add the check (with a matching `test/*.pas`
negative test in our own suite) → unskip. Split out sub-tickets if any check
turns out deep.

## Gate
`make test` + self-host byte-identical; burn the skip-list entries.
