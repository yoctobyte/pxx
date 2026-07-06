---
prio: 45  # auto
---

# Esoteric probe: LOLCODE

- **Type:** feature — esoteric-frontend-probe
- **Status:** backlog
- **Umbrella:** [[feature-esoteric-frontend-probes]]
- **Opened:** 2026-07-05

## What it is

Lolspeak-themed esolang: `HAI`/`KTHXBYE` (program bounds), `I HAS A` (declare),
`VISIBLE` (print), `GIMMEH` (read), `O RLY?`/`YA RLY` (if), `IM IN YR`/`IM
OUTTA YR` (loop), `SMOOSH` (string concat). Dynamically typed with loose
implicit casting between string/int/float/bool.

## Why it's a good probe

Dynamically typed + loosely cast — different type-checking path than anything
static-typed PXX parses today. Closest existing comparison is Nil Python's
dynamic surface; this hits it from a different, sillier angle. Likely the
cheapest candidate in the umbrella — no generics, no ownership, no exotic
control flow beyond what BASIC already has.

## Scope (skeleton only — see umbrella for the category rule)

Lexer + parser for the subset above, lowering onto existing IR (probably via
the same boxed/tagged-value approach Nil Python's dynamic typing already uses).
Stop once a trivial `HAI ... VISIBLE "HAI WORLD" ... KTHXBYE` program compiles
and runs, or a shared-internals bug surfaces trying to get there.

## Acceptance

Either: (a) a shared IR/codegen/ABI bug is found and filed as its own Track A
ticket, or (b) the trivial subset compiles and runs clean — both are a
successful, closed probe. Do not extend past the trivial subset either way.

## Log
- 2026-07-05 — filed as part of the esoteric-frontend-probes umbrella.
