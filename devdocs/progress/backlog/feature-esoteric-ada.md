# Esoteric probe: Ada

- **Type:** feature — esoteric-frontend-probe
- **Status:** backlog
- **Umbrella:** [[feature-esoteric-frontend-probes]]
- **Opened:** 2026-07-05

## What it is

Strongly statically typed, `begin`/`end`-block imperative language, same
Pascal/Algol family lineage as PXX's own primary language. Packages,
strong range-checked types, tasking (concurrency) in the full language.

## Why it's a good probe

User's own hunch: "should be trivial," because Ada is close kin to Pascal
(declaration shape, block structure, strong typing) rather than a foreign
paradigm. Good sanity check that the IR's Pascal-shaped assumptions actually
generalize to a close cousin rather than being accidentally Pascal-specific —
if this ISN'T trivial, that itself is an interesting finding (means the IR is
more Pascal-coupled than assumed).

## Scope (skeleton only — see umbrella for the category rule)

Lexer + parser for a trivial procedural subset (procedures, basic types,
`if`/`loop`, `Put_Line`-equivalent output) — no packages, no tasking, no
generics-with-instantiation. Stop once a trivial "hello world"-shaped program
compiles and runs, or a shared bug surfaces trying to get there.

## Acceptance

Either: (a) a shared IR/codegen/ABI bug is found and filed as its own Track A
ticket, or (b) the trivial subset compiles and runs clean — both close this
probe successfully.

## Log
- 2026-07-05 — filed as part of the esoteric-frontend-probes umbrella.
