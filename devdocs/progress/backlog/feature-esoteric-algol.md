---
prio: 45  # auto
---

# Esoteric probe: Algol (60)

- **Type:** feature — esoteric-frontend-probe
- **Status:** backlog
- **Umbrella:** [[feature-esoteric-frontend-probes]]
- **Opened:** 2026-07-05

## What it is

Algol 60 — the direct syntactic and structural ancestor of Pascal (Wirth
designed Pascal as Algol's successor). `begin`/`end` blocks, strong static
typing, `procedure`/`function`, call-by-value and call-by-name parameters,
nested procedures with lexical scoping. Historically significant as the
common ancestor of the whole Algol-family tree (Pascal, Simula, and — through
Simula and C — much of the modern imperative/OO lineage).

## Why it's a good probe — sharper than Ada's version of the same test

The umbrella's real goal (per user correction, 2026-07-05) is **proving
AST/IR correctness**, not "compile language X" for its own sake — the
compiling part is the funny side effect, not the point. Ada already tests
"does the IR generalize to a close cousin, or is it quietly Pascal-specific."
Algol tests the same question with a sharper instrument: it's Pascal's
**direct parent**, not a sibling descending separately from the same family.
If a trivial Algol 60 subset doesn't lower cleanly onto the existing IR,
that's a stronger, more surprising signal that the IR baked in
Pascal-specific assumptions somewhere — there's less excuse for kinship
friction against your own direct ancestor than against a cousin.

## What already exists to reuse (expected, not yet confirmed — check when picked up)

Expected to be the closest possible fit of any esoteric candidate:
- `begin`/`end` block structure — direct match, no translation needed.
- `procedure`/`function` declarations, static typing — direct match.
- Nested procedures with lexical scoping — PXX already supports nested
  procedures (used by Pascal itself); should be a near-free reuse.
- Call-by-name parameters (Algol's famous, unusual-by-modern-standards
  parameter-passing mode — a thunk-like re-evaluation on each use, not a
  simple pass-by-reference) are the one genuinely foreign piece — no direct
  PXX equivalent, and the classic "Jensen's device" trick depends on it.
  Cut for v1: call-by-value and call-by-reference only, skip call-by-name
  entirely (document the cut, don't quietly ignore it).

## Explicit non-goals (v1 scope cut)

- **No call-by-name parameters** — see above, the one real semantic gap;
  deferred, not free.
- **No `own` variables** (Algol's static-storage-duration locals) unless
  trivially free via existing static/global storage — check, don't assume.
- **Compiling arbitrary historical Algol 60 codebases** is obviously out of
  scope — vanishingly little exists to compile anyway; this is purely a
  structural probe.

## Scope (skeleton — capped per the umbrella's category rule)

Lexer + parser for a trivial subset: `begin`/`end`, `procedure`/`integer
procedure`, `if`/`then`/`else`, `for` (Algol's is more general than Pascal's —
cut to a simple counting form for v1), basic I/O equivalent. Stop once a
trivial program compiles and runs, or a shared bug surfaces trying to get
there — per the umbrella, either outcome closes this probe successfully.

## Acceptance

Either: (a) a shared IR/codegen/ABI bug is found and filed as its own Track A
ticket, or (b) the trivial subset compiles and runs clean — both close this
probe successfully, per the umbrella's inverted-success-criteria rule.

## Log
- 2026-07-05 — filed as part of the esoteric-frontend-probes umbrella, added
  when the user pointed out Algol/Fortran/Lisp/COBOL (1957-59) as candidates;
  Algol specifically promoted to its own ticket as a sharper kinship test
  than Ada (direct ancestor, not a sibling).
