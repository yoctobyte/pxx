---
prio: 45  # auto
---

# C GNU statement expressions ({ ... }) + __builtin_expect

- **Type:** feature (GCC extension, kernel-style code). Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing tests
- 00213: statement exprs in dead ternary arms containing labels — code
  suppression semantics. "expected C expression" line 15.
- 00214: `({ ... })` value-yielding blocks + `__builtin_expect(!!(x), 0)`
  (expect can be a pass-through builtin returning arg 1).

Needed for tcc/zlib-adjacent real-world code (corpus plan step 2/3).

## Gate
Drop 00213.c/00214.c from test/c-conformance/pxx.skip; runner green.

## Triage 2026-07-07
Even the BASIC `int x = ({ int t=20; t+22; });` fails (CERR) — no value-producing
block exists. Needs: (1) ParseCPrimary to detect `(` immediately followed by `{`
and parse a statement-expression; (2) a value-yielding block mechanism (new AST
node, or AN_SEQ/AN_BLOCK carrying the last expression-statement's value) + its
IR lowering. 00213/00214 additionally need the GNU dead-code / code-suppression
semantics (statement-exprs in dead ternary arms). Multi-part feature (parser +
new AST/IR node + lowering), a focused session — not a bounded fix.

## Progress 2026-07-08 (a-agent) — 00214 FIXED (basic statement expressions)
Implemented GNU statement expressions: a `(` immediately followed by `{` in
ParseCPrimary now parses the brace block (ParseCStmtExprAST) and yields a VALUE —
the last statement when it is an expression, else void(0). Modelled as
AN_COMMA(block-of-earlier-statements, value-expr); the comma lowering runs the
block for side effects then yields the value. Block-scope locals are unhooked on
exit (same teardown as ParseCBlockAST); AST value nodes hold sym indices so a
value expression referencing a block local still lowers. `__builtin_expect` was
already handled, so 00214 now passes.

00214 green. Conformance 212 pass / 0 fail / 8 skip. Self-host byte-identical,
quick tier + lua/core green. Dropped 00214 from pxx.skip.

(Landmine: comments must NOT contain literal `{`/`}` — nested comments are ON, so
a braced example in a comment desyncs the self-host lexer. Reworded to prose.)

**Remaining (ticket stays open):** 00213 — statement expressions in DEAD ternary
arms containing labels (`1 ? a : ({ ...some_label: ...; goto some_label; })`).
Needs GNU dead-code SUPPRESSION semantics: the dead arm must emit no code except
forward jumps, yet a label inside it reachable by `goto` un-suppresses. A
specialized code-suppression/label-reachability feature, separate from the basic
statement-expression value mechanism landed here.
