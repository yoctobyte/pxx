# Terminal ANSI library

- **Type:** feature
- **Track:** B
- **Status:** done
- **Owner:** Antigravity (Track B)
- **Opened:** 2026-06-20
- **Relation:** Track B library. Needed by console demos that want richer
  rendering without each app hand-rolling escape sequences.

## Goal

A small `Terminal` / `AnsiTerm` unit for console rendering primitives:
foreground/background colors, truecolor escape sequences, text attributes,
cursor movement, clear-screen, and optional terminal-size query.

The demo apps should call library helpers, not concatenate raw escape strings in
their own engines.

## Surface sketch

- `AnsiColor(fg: Integer; const s: AnsiString): AnsiString`
- `AnsiRGB(fgR, fgG, fgB: Integer; const s: AnsiString): AnsiString`
- `AnsiBgRGB(r, g, b: Integer): AnsiString`
- `AnsiReset`, `AnsiBold`, `AnsiClear`, `AnsiMove`
- optional: `TerminalSize(var cols, rows: Integer): Boolean`

## Acceptance

- A focused library test prints deterministic escape sequences and validates the
  exact bytes.
- `examples/adventure` can migrate its color helpers to this unit without
  changing game logic.
- Console output still works on targets without terminal-size support; queries
  return `False` rather than crashing.

## Notes

- Keep this independent from image rendering. Image-to-ANSI should consume this
  layer, not own terminal control itself.
- ESP/serial consoles may only support a subset; the API should degrade cleanly.

## RESOLVED 2026-06-21 (Track B)

Implemented `lib/rtl/ansiterm.pas` defining truecolor and standard ANSI sequence formatting functions. Added `test/lib_ansiterm.pas` unit test to verify exact escape sequences, avoiding compile-time constant-folding compiler bugs via runtime variable checks. Added `lib_ansiterm` execution to the Makefile `lib-test` suite.

**Resolved-in:** 2d7e65c (finalizing commit)
