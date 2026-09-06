---
track: P
prio: 55
type: bug
blocked-by: []
status: done
owner: "frankD"
created: 2026-09-06
summary: "FIXED 2026-09-06. `CurTokenText[1]` — a BARE call to the enclosing class's own parameterless method, indexed — dropped its `[`: `expected ')' before '['` in an expression, `a statement cannot start with '['` in a statement. Neither diagnostic mentions a return type, which is what the defect was. The implicit-Self dispatch in pasparser_expr.inc applied a trailing selector ONLY when the method returned tyClass or tyRecord; every other kind fell through with the bracket unconsumed. THREE SIBLING SPELLINGS OF THE SAME CALL ALREADY WORKED and that is what made it findable: `Self.Txt[2]`, `p.Txt[2]` and a bare global `GT[1]` all indexed correctly, because each reaches `ApplyCallResultPtrSuffix` — pasparser_lval.inc's self-described ONE materialisation point for a suffix on a call RESULT, which handles `.`, `[`, `^` and `(` over strings, arrays, pointers and metaclasses. Fixed by the arm joining that funnel rather than by a third member on its list; the class/record branch stays because ParseClassRecordSelectors needs the receiver's ci. Test `test_indexing_a_bare_implicit_self_method_result` (test-core#236). Unblocked fcl-passrc rung 7 pparser.pp, which advanced from :2468 to :4768."
---

# Indexing the result of a bare implicit-Self method call

- **Type:** bug — **Track P** (`compiler/pasparser_expr.inc`).
- Found in fcl-passrc rung 7, [[feature-pascal-corpus-expansion]]; the third
  wall in `pparser.pp`.

```pascal
function TPasParser.ParseExprOperand(...): TPasExpr;
begin
  ...
  if not (length(CurTokenText)=1) or not (CurTokenText[1] in ['A'..'_']) then
```

## The boundary, measured

At the unfixed binary, four spellings of one call:

| spelling | before |
| --- | --- |
| `Txt[1]` bare, inside a method | **refused** |
| `Txt()[1]` bare, explicit parens | **refused** |
| `Self.Txt[1]` | ok |
| `p.Txt[1]` from outside | ok |
| `GT[1]`, a bare global function | ok |

and, by return kind, bare: a dyn-array result **refused**, a class result ok.

## Why it is the enumerated-predicate shape, not a missing feature

```pascal
if (mpi >= 0) and (CurTok.Kind in [tkDot, tkLBrack]) and
   ((Procs[mpi].RetType = tyClass) or (Procs[mpi].RetType = tyRecord)) then
```

A hand-maintained list of return kinds that must grow a member per kind, with
**no diagnostic when it does not**. And the failure is the family's signature:
the diagnostic is about the WRONG SUBJECT — a bracket in a statement, a missing
paren in an expression — so a reader chases the expression grammar. The
operational tell held: the diagnostic was about the wrong subject, and one level
up there was a list.

The list also *cannot* be right, because the machinery it was approximating
already exists and is documented as singular: `ApplyCallResultPtrSuffix` is
declared in `pasparser_lval.inc` with the comment *"the ONE materialisation
point for a suffix on a call RESULT"*. Three of the four spellings reach it. So
this was never a widening question — one arm had opted out of the funnel and
grown a two-member approximation of it.

## Diagnosing it cost more than fixing it, and both instruments lied

`pascal26:2468: error: expected ')' before ','` — the **line was right and the
`near:` window was wrong**, pointing at `ParseExc(...)` on line 2301, 167 lines
away. Two hypotheses died on the near-text before a cut sweep settled it:
truncating `pparser.pp` at successive top-level boundaries and asking only
whether the paren error appeared. `TokenToExprOp` alone parsed clean; including
`ParseExprOperand` produced it.

Two of my own instruments also answered about something else. Stubbing the
suspect function moved the error to its own HEADER, which read as "the imbalance
predates this function" and was an artefact of the stub. And a predicate that
grepped the WHOLE compiler output for `expected ')'` reported True on a run whose
first error was `undefined variable (charinset)` — the string was present, from a
later line. Grep the first line, not the output.

## Residual found while cutting

Truncation surfaced a wall the parse error was hiding: `pparser.pp:559` uses
`charinset`, which `lib/rtl/sysutils.pas` does not declare (it names
`TSysCharSet` in a comment as *"the parameter type of the CharInSet / character"*
and then never declares the function). Filed as
[[feature-b-sysutils-charinset]].

## Log

- 2026-09-06 — fixed, commit PENDING-COMMIT.
