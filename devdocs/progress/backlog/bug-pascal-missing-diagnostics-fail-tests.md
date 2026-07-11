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

## 2026-07-11 — 24 more exposed by the headerless-program fix

The mandatory `program` header was accidentally rejecting 24 headerless
`{%FAIL}` negative tests before their actual invalid construct was ever
reached. With bug-pascal-headerless-program fixed, pxx now COMPILES them —
each is a real missing-diagnostic gap. From the conformance run (skiplist
reason "missing diagnostic: accepts invalid code"):

tcase3/6/9/10/11/19/20/23/26/27/35/36/39/42/43 (case-of-string validation:
overlapping/inverted ranges, duplicate labels), tclass13c, tenum2, tforin20,
tgeneric13/14/20/21, toperatorerror, tover3.

The tcase cluster is the bulk: case-statement label validation (duplicate
labels, inverted ranges) is simply not checked today.
