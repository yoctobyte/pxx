# Ilja — TUI (ANSI) face

- **Type:** feature (app / demo)
- **Status:** backlog
- **Track:** B
- **Parent:** feature-eliah-ide
- **Opened:** 2026-06-22

## Goal

Second face of the IDE: ANSI/TUI, reusing the **same garin core** (buffer,
docmodel, project, builder). Single full-screen terminal layout, box-draw tiled
panes — same product, different renderer.

## Scope

- `apps/ide/ilja/` — render + input + layout via `lib/rtl/ansirender.pas` +
  `ansiterm.pas`. Tiled panes with box-draw chars; editor, designer (boxes drawn
  as nested ANSI rectangles), output, props.
- Input: kbd primary; mouse optional (xterm SGR 1006). Resize widget = kbd nudge
  and/or mouse drag (decide at build).
- Reuse garin unchanged — proves the model is render-agnostic. Any leakage of
  GUI assumptions into garin = bug to fix in garin.

## Open questions (resolve at start — deferred B–E from design chat)

- B: is there a shared thin canvas interface, or fully separate paint code?
- C: TUI resize input model (kbd nudge vs mouse drag).
- D: color depth (256 / truecolor / 16-floor).
- Coord mapping: garin px → cells (cell ≈ 8×16 px) rounding rule.

## Acceptance

Ilja runs in a terminal, drives the same garin models as Eliah; editor + box
designer usable. garin needed no GUI-specific change.

## Log
- 2026-06-22 — filed (depends on M1; reuses garin).
