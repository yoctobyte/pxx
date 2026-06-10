# Valued defines + numeric `{$IF}` evaluation

- **Type:** feature
- **Status:** backlog
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
