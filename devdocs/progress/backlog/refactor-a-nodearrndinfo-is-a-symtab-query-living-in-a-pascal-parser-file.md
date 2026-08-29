---
track: A
prio: 30
type: refactor
blocked-by: []
summary: "NodeArrNDInfo contains no Pascal syntax and no Pascal semantics — it is a pure symbol-table query (SymArrNDims / UFldArrNDims / SymArrDimSpan) that happens to live in pasparser_call.inc. Track C now calls it across the frontend boundary, which the-substrate-is-ast-and-ir-not-the-parser.md warns against. The doctrine violation is the FILE, not the call: move it to symtab.inc."
status: backlog
owner: unassigned
---

# NodeArrNDInfo is a symtab query living in a Pascal parser file

- **Type:** refactor (doctrine) — **Track A file decision**, touches P.
- **Found:** 2026-08-30 (frankC), landing
  [[refactor-c-one-array-shape-reader-instead-of-four-ident-field-pairs]].
  Raised rather than decided: moving a function out of P's file is not Track
  C's call, and I have a recommendation, not an answer.

## The fork

`compiler/cparser.inc`'s new `CNodeArrayShape` calls `NodeArrNDInfo`, which
lives in `compiler/pasparser_call.inc`. `devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md`
says plainly: **share the AST and the IR; duplicate the parser, the lexer and
their support functions per language** — "a shared parser helper couples two
specs and is wrong in both."

Read literally, the call I just shipped is the thing that document forbids.
Three ways out:

| option | cost |
| --- | --- |
| **(a) move it to `symtab.inc`** (recommended) | one file move + include-order check; P and C both call it from shared ground, no duplication, no cross-frontend call |
| (b) duplicate it into `cparser.inc` as `CNodeArrNDInfo` | honours the letter of the doctrine; buys a second copy of a shape query that will drift — the precise failure this whole ticket family is about |
| (c) leave the cross-file call | cheapest today, and the next reader has no way to tell whether it was reasoned or accidental |

## Why (a)

The doctrine's subject is **specs**, not files: a shared *parser* helper is
wrong because two languages disagree about syntax and about what a construct
means. `NodeArrNDInfo` encodes neither. Its entire body reads `SymArrNDims`,
`SymPtrElemNDims`, `UFldArrNDims`, `SymArrDimLo/Span`, `UFldArrDimLo/Span` —
`symtab.inc` and `defs.inc` tables, shared substrate that every frontend
already writes. "What shape is this array symbol" has one right answer across
all five languages, the way `RecSize` and `TypeSize` do, and both of those live
in `symtab.inc` already.

So the defect is that the function is **filed** in a parser, not that C called
it. Its name says as much: it is the only `Node*` helper in that file with no
`Pas`/`Parse` in it.

Duplicating instead — option (b) — would be the doctrine applied past its own
reason, and it produces exactly the artifact this ticket family keeps finding:
two copies of one shape query, one of which is missing an arm.

## If (a) lands

[[refactor-p-nodearrndinfo-answers-nothing-for-a-rank-1-array]] and
[[refactor-p-nodearrndinfo-yields-spans-but-not-the-element]] move from P to A
with it; both are filed against P today because that is where the file sits.

## Gate

`make compiler/pascal26` (the move must be inert — include order: `symtab.inc`
precedes every parser, and `ResolveNodeRec`/`FindUField` are already forward-
declared there), plus Track T's sweep for the P/N/C callers.
