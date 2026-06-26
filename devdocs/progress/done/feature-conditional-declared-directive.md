# `{$IF DECLARED(...)}` conditional directive support

- **Type:** feature (Track A compiler / conditional directives)
- **Status:** done
- **Owner:** Track A
- **Opened:** 2026-06-21 (Synapse POSIX profile smoke)
- **Relation:** unblocks `feature-networking` / Synapse Delphi-`Posix.*` path;
  follows the existing directive-expression evaluator work

## Problem

Synapse's Delphi-POSIX socket include probes platform constants with
`{$IF DECLARED(Qualified.Symbol)}`:

```pascal
{$IF DECLARED(Posix.StrOpts.FIONREAD)}
FIONREAD = Posix.StrOpts.FIONREAD;
{$ELSE}
FIONREAD = {$IFDEF ANDROID}$541B{$ELSE}$4004667F{$ENDIF};
{$ENDIF}
```

The pinned stable compiler currently fails the POSIX-profile Synapse smoke with:

```text
pascal26:177: error: conditional directive: expected operator ()
```

This is a compiler feature gap. The library side should not edit Synapse or
replace these probes with hand-written constants just to get past parsing.

## Required behavior

- Accept `DECLARED(...)` as a boolean operator inside `{$IF ...}` expressions.
- Support qualified symbols, at least `UnitName.Symbol` and
  `Namespace.Unit.Symbol`, because Synapse probes imported `Posix.*` constants.
- Evaluate true when the symbol is visible at that source location and false
  when it is not.
- Compose with the existing conditional expression operators (`not`, `and`,
  `or`, parentheses) without changing `DEFINED(...)` behavior.

## Non-goals

- Do not implement a Synapse-only special case.
- Do not silently treat unknown directive functions as false; unsupported
  conditional functions should still fail loudly.
- Do not implement the `Posix.*` constants in this ticket. This ticket only makes
  the conditional probe expressible.

## Acceptance

- A focused test proves `{$IF DECLARED(LocalConst)}` selects the true branch.
- A focused test proves `{$IF DECLARED(MissingConst)}` selects the false branch.
- A focused test proves `{$IF DECLARED(Posix.StrOpts.FIONREAD)}` works when a
  stub dotted unit exports that constant.
- Re-running
  `SYNAPSE_PROFILE=posix test/manual/try_synapse_compile.sh` no longer fails at
  `ssposix.inc` with `conditional directive: expected operator`.

## Log

- 2026-06-21 — filed from Track B Synapse smoke. This is the first parser
  failure after forcing Synapse toward the desired Delphi-POSIX socket branch.
- 2026-06-21 — DONE. `DECLARED(name)` added to the `{$IF}` expression evaluator
  (lexer.inc, alongside `defined`). Resolution insight: conditionals are
  evaluated during LexAll/LexAppend, so the only knowable symbols are those whose
  declaration has already been emitted into `Tokens[0..TokCount-1]` — exactly
  "visible at this source location" in PXX's lex-ordered model. `PasCondNameDeclared`
  scans the emitted token stream with a small const/type/var/routine section state
  machine; `ReadPasCondQualifiedName` reads dotted names and the final component is
  matched. Composes with `not`/`and`/`or`/parens; unknown directive functions still
  fail loudly (non-goal honored). Regression test `test/test_declared_directive.pas`
  (in `make test-core`) covers all four acceptance probes; gate green (self-host +
  threadsafe byte-identical).
  - Acceptance 1 (`DECLARED(LocalConst)` → true): PASS.
  - Acceptance 2 (`DECLARED(MissingConst)` → false): PASS.
  - Acceptance 3 (qualified positive): PASS via final-component match when the
    symbol is in-stream. LIMITATION: namespace-precise qualified resolution
    (checking the *unit*, not just the leaf name) is deferred to
    `feature-dotted-unit-names`; for now `A.B.leaf` resolves on `leaf` alone.
  - Acceptance 4 (Synapse smoke): PASS — `ssposix.inc` no longer errors with
    `conditional directive: expected operator`. The POSIX-profile probes
    (`Posix.StrOpts.*`, no such unit) correctly evaluate false → Synapse takes the
    `{$ELSE}` literal. Synapse now advances to the *next* gap,
    `uses: unit source not found: posix` (the `feature-dotted-unit-names` /
    unit-resolution work — out of scope here per non-goals).
