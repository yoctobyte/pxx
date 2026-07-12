---
prio: 48  # auto — 8 conformance tests
---

# `class operator` + named operators (Initialize/Finalize/Explicit/...)

- **Type:** feature (Pascal frontend, operator overloading)
- **Track:** P (shared `parser.inc` — A-gated)
- **Status:** working
  ([[feature-pascal-corpus-fpc-testsuite]]).
- **Owner:** opus-p

## Symptom
`error: expected operator symbol after operator keyword` — pxx parses only
symbol operators (`operator +` etc.). Missing:
- **management operators** in advanced records: `class operator
  Initialize/Finalize/AddRef/Copy(var a: TFoo)` (tmoperator*) — these have
  *semantics* (compiler-invoked at var lifetime events), not just parse;
- named conversion/logic operators FPC accepts (`Explicit`, `:=`
  assignment-operator spelling, `in`, `inc`, `dec`).

## Impact
8 curated failures (`tmoperator*`, `tassignmentoperator1`, some `toperator*`).
Skip-list reason: `parser: named/class operator`.

## Note
Parse-side is P; the lifetime-event *invocation* (Initialize on entry,
Finalize on scope exit) likely needs IR/lowering support → that part is a
Track A ticket when reached.

## Gate
`make test` + self-host byte-identical; burn the skip-list entries.

## Slice 1 landed (2026-07-12, opus-p)

Named operators on RECORD/CLASS operands parse + dispatch:
- `operator :=` / `Implicit` — implicit conversion at assignment (ir.inc
  AN_ASSIGN rewrites the RHS to the conversion call when types differ and the
  overload's result type matches the LHS).
- `operator Explicit` — fires at value casts (both the ident castTk branch and
  the tkInteger_T branch in ParseFactor).
- `operator Inc/Dec` — the Inc(x)/Dec(x) statements desugar to x := Op(x)
  (single-operand form only, like FPC).
- `Enumerator` + management ops parse+register but are NOT dispatched yet.
Conformance: toperator11 burns. Test: test/test_named_operators.pas.

## Slice 2 landed (2026-07-12, opus-p)

`operator Enumerator` DISPATCHES in for-in: a class/record (or string-typed)
container with a registered enumerator overload builds the same duck-typed
MoveNext/Current[/Free] loop as GetEnumerator, over the operator call.
Scalar operand types also register now (LongInt/String/...; String under
both managed+frozen kinds), and conversion/unary operators enforce 1-param
arity (binary = 2). Conformance: tforin5 + tassignmentoperator1 burn
(3 total with toperator11). Tests: test_named_operators,
test_operator_enumerator.

**Remaining:**
- operators on NON-record operand types (String/LongInt operands —
  tforin2, tgenfunc8/10, tassignmentoperator1): needs the OvrlType table +
  dispatch to accept scalar tks (recId REC_NONE), and the scalar binop hot
  path to consult it.
- `operator Enumerator` dispatch in for-in (tforin2/5/24).
- `class operator` INSIDE advanced records (tmoperator*) — member-decl parse
  plus the Initialize/Finalize lifetime EVENTS, which are IR work → file the
  Track A ticket when picked up.
