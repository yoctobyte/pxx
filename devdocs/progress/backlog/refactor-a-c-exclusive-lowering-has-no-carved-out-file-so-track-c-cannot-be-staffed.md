---
track: A
prio: 45
type: refactor
status: backlog
blocked-by: []
owner: ""
summary: "C owns its lexer/parser/preproc but NOT its lowering: ir.inc carries 40 CProgramMode references. So most Track C work needs Track A's files, and a C agent cannot be staffed independently -- measured 2026-08-29, four of six ranked C tickets need an A file."
---

# C-exclusive lowering has no carved-out file, so Track C cannot be staffed independently

- **Type:** refactor (structural / coordination) — **Track A** (owns `ir.inc`).
- **Found:** 2026-08-29 by frankC, working down the Track C queue; measured and
  confirmed by the coordinator.

## The measurement

Track C owns `clexer.inc`, `cparser.inc`, `cpreproc.inc` and `lib/crtl`. It does
**not** own a lowering file — there is no `cir.inc`. C-exclusive lowering lives
in the shared `compiler/ir.inc`, which carries **40** `CProgramMode` references.

The consequence, over the six ranked Track C tickets:

| ticket | file it must edit | workable by a C-only agent? |
| --- | --- | --- |
| `refactor-c-string-literal-decay-belongs-at-the-producer` [p50] | `ir.inc` | **no — A** |
| `feature-c-diagnostics-name-the-module-they-are-in` [p40] | `lexer.inc` | **no — A** |
| `refactor-c-the-partial-index-sentinel` [p40] | `cparser.inc` + `ir.inc` | **no — C+A** |
| `feature-c-import-a-pascal-unit-under-a-mangled-name` [p50] | — | no — blocked on the user |
| `idea-c-realworld-test-targets` [p60] | — | no — brainstorm parent |
| `compat-c-printf-p-of-null` [p22] | `lib/crtl` | yes — **resolved `e885d94ef`** |

**`ready --track C` prints nine items; exactly one was workable, and it is now
done.** That gap is why "Track C has a queue and no agent" read as an easy
staffing win on 2026-08-29 and was not one.

## Why this is a real defect and not just how it is

The tracks are **file-lanes for collision avoidance**. A lane whose work
predominantly lands in another lane's files is not a lane — it is a label, and
it silently converts every C dispatch into a request for the A slot. Compare:

- **P** had exactly this problem and it was fixed. The 37,249-line `parser.inc`
  was sliced into `pasparser_*.inc` on 2026-08-20 precisely so Pascal frontend
  work would stop needing A's slot. (Its lexer is still shared — the known
  residual.)
- **R** and **Z** own `rparser.inc` / `zparser.inc`.
- **N** owns `pylexer.inc` / `pyparser.inc` and is explicitly called out in
  CLAUDE.md as the low-risk combination *because* it is carved out.

C is the frontend that got its parser carved out and its lowering left behind.

## It is a half-finished migration, not a design choice

frankC's framing, added 2026-08-29 and sharper than the original: **C is the only
mainline frontend whose parser was carved out and whose lowering was not.** That
makes the asymmetry a migration nobody finished rather than a deliberate split —
which is what turns this into a refactor with a **known-good precedent** (the
`pasparser_*` split of 2026-08-20) instead of an open design question. Nobody has
to decide whether C *should* own its lowering; every other frontend already does.

It also predicts the payoff, which the table above does not. A `cir.inc` would move
`refactor-c-string-literal-decay`, `refactor-c-the-partial-index-sentinel` and
probably `feature-c-diagnostics-name-the-module` from "needs the A slot" to
"ordinary C work" — **three of the four tickets that made the lane unstaffable.**
The value is not tidiness; it is that Track C becomes dispatchable in parallel with
Track A, which it is not today.

## What to do

Carve C-exclusive lowering out of `ir.inc` into `cir.inc`, the way
`pasparser_*.inc` was carved out of `parser.inc`. The 40 `CProgramMode` sites
are the starting inventory, not the definition — some will be genuine shared
decisions that must stay.

**Do not treat the count as the scope.** The `parser.inc` split's lesson was
that the machinery which was never Pascal went to its real owner (`ast_arena`,
`inline_expand`, `ast_syminfer` to A; NilPy's forwards to N). Expect the same
here: some of the 40 are C-shaped things that belong to C, and some are shared
lowering with a `CProgramMode` guard bolted on, which is a different defect.

## Until then

Track C is **one agent's worth of work at a time, gated on the A slot**, not an
independently staffable lane. A coordinator staffing C should either pair it
with the A slot or expect it to run dry. That is the operational fact this
ticket exists to remove.
