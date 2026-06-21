# `{$IF DECLARED(...)}` conditional directive support

- **Type:** feature (Track A compiler / conditional directives)
- **Status:** backlog
- **Owner:** —
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
