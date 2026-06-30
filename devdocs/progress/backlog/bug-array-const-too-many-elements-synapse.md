# `too many array constant elements` — Synapse `synautil` wall

- **Type:** bug/limit (parser capacity) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30 (found in triage; new wall past the now-fixed blockers)

## Symptom

`uses synautil; --mimic-fpc` (Synapse) now compiles past its two former blockers
(bug-chr-builtin-shadows-param-name, bug-consteval-named-type-cast, both done) and
hits: `error: too many array constant elements`. A large typed-array constant
(lookup table) exceeds a fixed `MAX_*` element ceiling in the array-constant parser.

## Direction

Find the `too many array constant elements` Error site (parser array-constant
path) and the `MAX_*` it checks; bump it (interim, like the other capacity bumps),
or make it dynamic ([[feature-dynamic-compiler-tables]]). Then re-probe synautil
for the next wall. Advances [[feature-synapse-compile-check]].

## Acceptance

`synautil` (and other large array-const sources) compile past this limit; the next
wall (if any) is identified; self-host byte-identical.
