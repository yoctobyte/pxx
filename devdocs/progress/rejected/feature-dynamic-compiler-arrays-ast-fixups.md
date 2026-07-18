---
summary: "Apply the dynamic-array pattern (proven on the IR arrays) to the other fixed compiler caps: AST nodes, global fixups, label arrays"
type: feature
prio: 25
---

# Dynamic-grow the remaining fixed compiler arrays (AST, fixups, labels)

- **Type:** feature / scalability (Track A — `defs.inc`, the owning `.inc`). Same
  shape as [[bug-pascal-ir-node-hard-limit-max-ir]], now RESOLVED for the IR arrays
  (`cf7bbcea`): a fixed `array[0..MAX_*-1]` both wastes always-resident BSS and
  hard-caps a single large function.
- **Status:** backlog, low prio (each cap is only hit by pathological / generated
  code, like the IR one was).

## The pattern (proven on IR)

1. Change `array[0..MAX_X-1] of T` → `array of T` (read/write `[i]` syntax
   unchanged, so no access site changes).
2. Add `EnsureXCapacity(need)` that doubles from a small base and grows ALL
   parallel arrays in lockstep; call it at the ONE append chokepoint.
3. Drop the `Error('X overflow')`.
4. Gate: self-host byte-identical (dogfoods pxx's own global-dynarray SetLength) +
   a generated over-cap test.

## The remaining caps (each surfaced while testing the IR fix)

- **`MAX_AST` (524288, effective 516096 — the tail is inline-reserve).** ~7 parallel
  `AST*` arrays (`ASTKind/ASTIVal/ASTSOffset/ASTSLen/ASTCLongRank/ASTLeft/ASTRight`,
  and any others). Chokepoint: `AllocNode` (find it; verify `ASTNodeCount` is written
  only there + the per-body reset). NOTE the inline splice reserves `[INLINE_AST_BASE
  ..MAX_AST)` — the dynamic version must preserve that two-region split (inline nodes
  live at the top and survive the per-proc reset), so growth/indexing there needs
  care. Highest-value: AST overflowed *first* for a big arithmetic function.
- **Global fixups** (`error: global fixup overflow`). The fixup table for global
  var/call references; overflowed by a function with tens of thousands of global
  references. Find the array + its append site.
- **`LabelPositions` / `LabelFixupPos` / `LabelFixupTarget`** (`array[0..MAX_IR-1]`,
  label-indexed — left static when the IR node arrays went dynamic). A function with
  > MAX_IR labels overflows; far rarer than nodes, but same fix.

## Non-goal / caveat

The **seq-walk recursion depth** (~3500 chained statements SIGSEGVs the compiler in
the recursive AST/IR tree walk) is a DIFFERENT problem — a stack-depth limit, not an
array cap. Converting arrays won't fix it; that needs an explicit worklist/iterative
walk (or a bigger compiler stack). File separately if it bites real code.

## Acceptance

Per array converted: self-host byte-identical, a generated over-cap test compiles +
matches FPC, `make test` green. Do them one at a time (AST first — highest value).

## SUPERSEDED 2026-07-18
Folded into [[feature-dynamic-compiler-tables]] (the canonical umbrella, which now
carries the proven incremental-on-master approach + IR/AST done + the remaining
priority list). AST is DONE (d11bf05a); the fixups/labels live under that ticket.
