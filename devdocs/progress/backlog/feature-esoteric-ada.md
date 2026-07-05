# Esoteric probe: Ada

- **Type:** feature — esoteric-frontend-probe
- **Status:** backlog — **chosen next pick** among the esoteric-probe candidates (2026-07-05)
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

## Why this one, ranked over the other candidates (2026-07-05)

Asked directly which esoteric-probe candidate to pick first: Ada, over
COBOL/Fortran/LOLCODE/Whitespace, for a reason distinct from "which is
easiest." The others (COBOL, Fortran, LOLCODE, Whitespace) mainly test
"does this exotic grammar shape parse and lower cleanly" — a novelty
question the C/Rust/Nil-Python diversity already covers reasonably well.
Ada tests something none of them can: **is the IR actually general, or
quietly Pascal-specific in ways nobody's noticed?** Same block-structure/
strong-typing family as Pascal, so if a trivial Ada subset *doesn't* lower
cleanly onto existing IR, that's itself the interesting finding — evidence
the "shared IR" story is more Pascal-coupled than assumed, worth knowing
regardless of Ada itself. Kinship test, not a novelty test — higher signal
per unit of effort than the others on this list.

(COBOL stays the pick if the goal shifts to pure fun-demo value instead —
its DIVISION-structured, English-like syntax is the best callback to the
session's "platonic language / closest to human expression" tangent.)

## Log
- 2026-07-05 — filed as part of the esoteric-frontend-probes umbrella.
- 2026-07-05 — chosen as the next pick when asked directly which candidate
  to prioritize; reasoning above. Not started, still backlog — a choice of
  *order*, not a greenlight to build yet.
