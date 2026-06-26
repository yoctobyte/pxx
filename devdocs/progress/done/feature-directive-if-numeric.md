# Valued defines + numeric `{$IF}` evaluation

- **Type:** feature
- **Status:** done
- **Owner:** —
- **Opened:** 2026-06-10 (split out of feature-mimic-fpc design)

## Problem

The conditional-expression evaluator (`EvalPasCondExprText`, lexer.inc ~577 —
shared by the lexer's `ProcessPasDirective` and the `ExpandIncludes` pre-pass,
so one change point) is a pure Boolean algebra:

- Value stack `PasCondValues` is `array of Boolean` — 1 bit wide.
- Op stack `PasCondOps` knows `(`, `!` (not), `&` (and), `|` (or).
- Tokenizer reads identifiers and parens only; anything else dies with
  `conditional directive: unexpected character`.
- Define tables (`PasDefineNameOff/NameLen/Active`) store name + flag. A
  define *is* or *isn't* — no value.

FPC-targeted compatibility headers evaluate, in their **live** branch:

```pascal
{$IF defined(FPC_FULLVERSION) and (FPC_FULLVERSION >= 20400)}
```

That needs an integer literal (`20400`), comparison operators (`>=`), and an
identifier that is `True` inside `defined()` but `30202` beside `>=`. The
inactive-branch eval skip (440a9e0) only protects *dead* regions; once
`FPC` is defined this expression is live. Hard prerequisite for
feature-mimic-fpc, but independently useful (version-gated user code).

## Design

1. **Value lane on the define table.** Parallel arrays
   `PasDefineValue: Int64` + `PasDefineHasValue: Boolean` (parallel-array
   convention — never grow a record). v1 values come from compiler
   presets/mimic init only; `{$DEFINE X:=value}` macro syntax is deferred.
   `ExpandIncludes` snapshots define state (count/charlen/active) around each
   expansion — the value lane must join that snapshot or unit-local `$DEFINE`s
   leak values.
2. **Tagged value stack.** Slot = (kind ∈ {bool, int}, payload). Two parallel
   arrays: `Int64` payload + kind tag. Comparisons pop two int slots, push
   bool; `not/and/or` demand bool slots. **Type mixing is a loud error** —
   `5 and TRUE` dies with a message, no silent coercion.
3. **Tokenizer learns two shapes.** Digit run → integer literal (decimal;
   `$hex` only if a real header needs it). One-char-lookahead operators:
   `= <> < <= > >=`, each encoded as a single char on the existing op stack
   (e.g. `=`, `#`, `l`, `L`, `g`, `G`).
4. **Identifier context rule.** Bare valued identifier → int slot; bare
   unvalued identifier → bool via `PasDefineExists` (today's behavior,
   unchanged — zero regression surface). `defined(X)` unchanged.
5. **Precedence.** Pascal order: `not` > `and` > `or` > relational.
   Comparisons enter `PasCondOpPrecedence` *below* `or`. Headers parenthesize
   comparisons anyway (Pascal forces the habit), but match the language.

## Non-goals

- Float literals (`RTLVersion >= 14.2` lives only in Delphi branches, dead
  under mimic) — clear error if reached, never mis-evaluate.
- `{$DEFINE X:=value}` source syntax (defer until a header needs it).
- String comparison, arithmetic operators (`+ - * div`) — add only on
  concrete demand.

## Acceptance

- Regression `test/test_directive_if_numeric.pas`: predefined valued symbol,
  `{$IF X >= N}` true/false both ways, `defined(X)` still works, `<>`/`=`/
  `<`/`<=`/`>`/`>=` covered, type-mix and float each produce a clear error.
  No mimic mode, no Synapse needed.
- Existing directive tests unchanged; `make bootstrap` fixedpoint holds.

## Log

- 2026-06-10 — ticket opened; split from feature-mimic-fpc ("hidden
  structural cost" item) after walking the evaluator machinery with user.
- 2026-06-21 — done. Value lane added as parallel arrays `PasDefineValue:
  Int64` + `PasDefineHasValue: Boolean` (defs.inc); `PasSetDefineValue` /
  `PasDefineLookupValue` helpers; `PasInitDefines` predefines valued
  `PXX_VERSION = 26`. ExpandIncludes snapshot (elfwriter.inc) extended to
  save/restore the value lane so unit-local defines do not leak values.
  Tagged value stack: parallel `PasCondValKind` (0=bool,1=int) + `PasCondInt:
  Int64`; `PasCondPushBool/Int` helpers. Tokenizer learns decimal integer
  literals (with a loud float-literal error on a trailing `.`) and one-char-
  lookahead relational ops `= <> < <= > >=` tagged `= # l L g G`. Precedence:
  not(4) > and(3) > or(2) > relational(1). Comparisons demand int operands;
  `not/and/or` route through `PasCondSlotAsBool`, which accepts a bool slot or
  an int that is exactly 0/1 (preserves the legacy `(...) and 1` idiom) and
  loud-errors any other int in a boolean op (`5 and TRUE`). Top-level bare int
  is FPC-truthy. Regression test `test/test_directive_if_numeric.pas` (+ float
  and type-mix negative tests) wired into `make test`. Self-host byte-identical
  (1-gen reseed via `make bootstrap`); all 5 cross/ESP targets emit. No pin —
  directives do not change emitted code shape.
