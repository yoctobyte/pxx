---
slug: refactor-a-the-pointer-suffix-walk-has-six-copies-in-the-pascal-frontend
title: "The `^`/`.`/`[]` suffix walk has six copies in the Pascal frontend, and none can be deleted alone"
track: A
prio: 55
type: refactor
blocked-by: []
status: working
owner: frankA
created: 2026-08-30
found-by: frankA (splitting item 4 out of feature-a-typeref-migrate-consumers)
summary: "The pointer/field/index suffix walk is duplicated SIX times in the Pascal frontend (not four, as the parent ticket says -- listed, not counted). Each copy stamps a different subset of the node tags the rest of the compiler reads, which is why four separate tickets have now ended 'the metadata was there, the reader was missing'. None can be deleted without the others agreeing on the tags, so this is one refactor, not six fixes."
---

# The suffix walk has six copies, and the reader is always the broken half

Split out of [[feature-a-typeref-migrate-consumers]], whose "still open" list
asks for exactly this and says to *"file it before starting, with the four sites
named"*. **There are six, not four** — the parent's count was never listed out.

## The sites, measured 2026-08-30 (listed, not counted)

| # | site | shape |
| --- | --- | --- |
| 1 | `pasparser_lval.inc:4770` | inside `ApplyCallResultPtrSuffix` (from :4722) — the call-RESULT suffix |
| 2 | `pasparser_expr.inc:930` | the `^`-or-`.` walk in the factor path |
| 3 | `pasparser_expr.inc:6391` | `[tkCaret, tkDot, tkLBrack]` |
| 4 | `pasparser_expr.inc:6740` | `[tkCaret, tkDot, tkLBrack]` |
| 5 | `pasparser_stmt.inc:6444` | `[tkCaret, tkDot, tkLBrack]` |
| 6 | `pasparser_stmt.inc:6559` | `[tkCaret, tkDot]` — note the SHORTER set, no index arm |

**Not in scope, deliberately:** `pyparser.inc:42567 / 47378 / 47524` are NilPy's
own three copies. Duplication *across* languages is the rule
(`the-substrate-is-ast-and-ir-not-the-parser.md`: share the AST and IR, duplicate
the parser), so those are correct as duplicates and must not be folded into the
Pascal ones. They are worth reading while doing this, because they are a second
opinion on what the walk must stamp — but they stay separate.

Site 6 having a shorter token set than the other five is the smell in miniature:
six copies of one concept, one of which quietly does not handle indexing.

## Why this is the valuable half

Four tickets in a row have ended with the same sentence — *the metadata was
there, the reader was missing*:

- `bug-p-dereferencing-a-function-result-of-pointer-to-pchar-loses-the-shape`:
  populating proc-return depth fixed **nothing** on its own. `c := GetQ^;
  WriteLn(c)` printed the string while `WriteLn(GetQ^)` printed the address —
  same binary, same declaration — because `ApplyCallResultPtrSuffix` stamped
  none of the node tags the rest of the compiler reads.
- The parent ticket's own conclusion: *"when a pointer shape is wrong, look at
  the reader before the table."*

So the table-folding work (`TTypeRef`) makes the *data* consistent, and this
makes the *consumers* consistent. The parent ticket judges this "a bigger,
better-value refactor than the table fold".

## The constraint that makes it one job

**None of the six can be deleted without the other five agreeing on the node
tags they stamp.** That is the whole difficulty and it is why this is filed as
one refactor rather than six small fixes: a partial merge leaves a caller whose
tags differ from its neighbours', which is the current state and the thing being
fixed.

## Suggested approach (not a prescription)

1. **Inventory what each copy stamps** — the node tags, not the parse. A table
   of six rows against the tag set is the deliverable that makes the rest
   mechanical, and it is most of the work.
2. Land the union as one helper, converting copies **one at a time**, each under
   the parent ticket's A/B binary-comparison standard (compiler built before and
   after, same sources, diffed) rather than "the tests pass". That standard is
   what caught the 2026-08-01 revert's absence, and it is the right one here
   because a tag that no current test reads is exactly what is being unified.
3. Expect the union to be strictly larger than any one copy. A copy that stamps
   fewer tags is not "simpler"; it is the one with the latent bug.

## Gate

Per converted copy: `make compiler/pascal26` + A/B binary identity across the
Pascal, C, BASIC and NilPy sources the parent ticket lists, plus the 72-pair
`GetQ^` cross product (10 shapes x 8 contexts) staying at 72/72 against
fpc 3.2.2. `tools/gate.sh quick` before any pin.

**Do not** take this concurrently with `feature-a-typeref-migrate-consumers`'s
step 2 — that one needs `ir.inc` and re-points `PtrBaseTk`, and these six
readers are downstream of exactly that field's meaning.
