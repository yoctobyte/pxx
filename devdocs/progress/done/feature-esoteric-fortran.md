---
prio: 45  # auto
---

# Esoteric probe: Fortran

- **Type:** feature — esoteric-frontend-probe
- **Status:** done (2026-07-06) — skeleton landed, ARG-decimals sharp edge documented, probe closed
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

## Probe done (2026-07-06, Track Z session)

Skeleton landed, free-form F90 per the ticket's scope call: `compiler/
flexer.inc` + `compiler/fparser.inc` (new), `isF90` + `.f90` dispatch in
compiler.pas, one-line var in defs.inc. Reuses rparser.inc node helpers.

**Landed subset:** PROGRAM/END PROGRAM, IMPLICIT NONE accepted-but-ignored
(implicit typing IS the probe), implicit first-letter typing at first
assignment (I-N -> tyInt64, else REAL -> tyDouble), PRINT * expr-lists,
IF (cond) THEN / ELSE / END IF, DO v = lo, hi [, step] with inclusive
bounds and constant integer steps incl. negative, modern comparison
operators, int->double widening via the shared RWiden. Out (loud errors):
** power, .EQ./.AND. dot-forms, arrays/calls, REAL DO variables. Test:
test/test_fortran_skeleton.f90 in make test.

**Probe verdict: one real frontend-API sharp edge found** (not a shared
codegen bug — the shared machinery is correct, but the contract is easy to
misuse): IR_WRITE reads per-arg formatting from the AN_ARG node as
ASTIVal = field width (0 = none) and ASTSOffset = decimals where -1 = NONE
— but AllocNode leaves ASTSOffset at 0, which is "zero decimals", so a
frontend that builds a print of a REAL and forgets to set the sentinel
silently prints 2.5 as "2". First frontend to print doubles outside the
Pascal parser, first to hit it. Fixed locally (fparser sets -1, with a
comment); flagging here rather than filing a Track A ticket since a default
change in AllocNode is a shared-semantics call A should make deliberately —
if another frontend trips this, promote it to a ticket.

Also confirmed: the codegen's built-in float formatter needs NO RTL pull
(0-proc binary prints scientific-notation doubles) — nice.

Acceptance (b) met (plus the sharp-edge documentation). Closed at skeleton
depth.
