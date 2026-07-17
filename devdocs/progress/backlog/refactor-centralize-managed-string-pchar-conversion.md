---
summary: "Centralize managed-string/PChar conversion — key on static type, not node shape; kill the recurring silent AnsiString class"
type: refactor
prio: 50
---

# Centralize managed-string conversion — stop enumerating node shapes

- **Type:** refactor (Track A — shared `ir.inc` / `parser.inc` lowering). Structural.
- **Status:** backlog
- **Opened:** 2026-07-17, from a user observation: "we keep finding AnsiString bugs — it's
  one managed type with features; all sub-features work individually, yet issues recur.
  This smells like we special-case it in too many places."
- **Motivating instance:** [[bug-pascal-ansistring-cast-of-cdecl-call-result]] (silent
  garbage length casting an external-call PChar result).

## The observation, and why it's right

The recurring AnsiString bugs are not many unrelated defects — they are **one structural
smell** surfacing in new spots. Evidence:

- **688** sites in `compiler/*.inc` branch on the string type
  (`tyAnsiString`/`tyString`/`IsManaged`): ir.inc 94, parser.inc 68, ir_codegen.inc 64,
  symtab 38, plus every backend.
- The **PChar→managed-string conversion is copy-pasted** (`FindProc('PCharToString')` +
  build wrapper) at ≥2 sites in `ir.inc` (cast 3937, assign 4917) — each independently.
- Every copy is gated on **`IsNodePChar`** (`ir.inc:1494`), which classifies by
  **node SHAPE**, not type: hand-written cases for cast-node / `AN_IDENT` / `AN_FIELD` /
  `AN_CALL`, each reading different metadata.

That is the bug engine: each new expression **shape** (external call, method result,
array element, ternary, `with`-field, …) or each new **context** (cast, assign, arg,
return, concat) is a case someone must remember to add to the enumerator AND a place to
re-paste the conversion. Miss one → a **silent** wrong value (the class every AnsiString
landmine in memory belongs to: not-on-lvalue, case-selector re-eval, forward-ptr-field,
byval-temp double-free, this cast bug).

## The fix — one type-keyed conversion, called everywhere

1. **`IsNodePChar` keys on the node's resolved static type**, not its shape. "Is this
   expression `^Char`/PChar?" is answerable from the inferred type for ANY node —
   deleting the four hand-cases and covering call/var/field/element/ternary uniformly.
2. **One `MaybeConvertPCharToString(node): node`** helper (the wrapper-build logic, once).
   Replace the copy-pasted blocks at the cast site, the assign site, and the
   arg/return/concat sites with a call to it.
3. Audit the other 688 `tyAnsiString` branches for the same duplication-of-a-decision
   pattern; fold the ones that are re-deriving "is this managed?" / "does this need a
   copy/finalize?" into shared predicates. (Incremental — do the PChar conversion first,
   it is the one drawing blood now.)

## Why this is worth a refactor, not just N point-fixes

Point-fixing each new shape as it's found is O(shapes × contexts) forever, and each miss
ships a silent bug to a user wrapping a C library. Centralizing is O(1): the next new node
shape is covered for free because it already has a static type. This is the
`ir-as-substrate` discipline applied inward — push the decision down to one place.

## Acceptance

- `IsNodePChar` (or its replacement) returns correctly for a PChar-typed value of ANY
  node shape, verified by a table test (var, local call, external cdecl call, field,
  array element, ternary).
- The cast/assign/arg/return PChar→string conversions route through one helper (grep for
  `FindProc('PCharToString')` collapses to 1 call site).
- [[bug-pascal-ansistring-cast-of-cdecl-call-result]] fixed as a consequence.
- Gate: `make test` + self-host byte-identical (this touches hot lowering — reseed
  discipline applies).

## Non-goals

- Not reworking the managed-string runtime/ABI — this is about where the compiler
  *decides* to convert, not how the RTL represents strings.
- Not a big-bang rewrite of all 688 sites — start with the PChar-conversion cluster
  (the active bleeder), widen opportunistically.
