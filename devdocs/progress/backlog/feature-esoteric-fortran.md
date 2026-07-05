# Esoteric probe: Fortran

- **Type:** feature — esoteric-frontend-probe
- **Status:** backlog
- **Umbrella:** [[feature-esoteric-frontend-probes]]
- **Opened:** 2026-07-05

## What it is

One of the oldest still-used languages; array-heavy numeric computing,
historically fixed-form source (columns 7-72 significant, columns 1-6
reserved for labels/continuation), `GOTO`-heavy control flow, and (pre-F90)
implicit typing by variable-name first letter (`I`-`N` = integer, else real)
unless overridden.

## Why it's a good probe

Genuinely different era and shape: column-position-sensitive lexing (if
targeting fixed-form) is unlike anything else attempted, array-first
semantics (multi-dimensional arrays as a primitive, not a library type)
stress a different path than PXX's dynamic-array model, and implicit
name-based typing is a different inference rule than anything else parsed.

## Scope (skeleton only — see umbrella for the category rule)

Pick free-form Fortran (F90+ style, not fixed-form columns) to dodge the
column-lexing complexity unless that specifically is the point of interest
later. Lexer + parser for a trivial subset (`PROGRAM`/`END PROGRAM`,
`PRINT *`, basic arithmetic, a `DO` loop) — no COMMON blocks, no modules, no
array-slicing syntax. Stop once a trivial program compiles and runs, or a
shared bug surfaces trying to get there.

## Acceptance

Either: (a) a shared IR/codegen/ABI bug is found and filed as its own Track A
ticket, or (b) the trivial subset compiles and runs clean — both close this
probe successfully.

## Log
- 2026-07-05 — filed as part of the esoteric-frontend-probes umbrella.
