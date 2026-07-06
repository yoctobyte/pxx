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
