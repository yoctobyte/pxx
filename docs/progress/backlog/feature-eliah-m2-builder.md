# Eliah M2 — builder integration

- **Type:** feature (app / demo)
- **Status:** backlog
- **Track:** B
- **Parent:** feature-eliah-ide
- **Blocked-by:** feature-eliah-m0-window
- **Opened:** 2026-06-22

## Goal

Wire the IDE to frankonpiler: build the open project, capture output, parse
compiler diagnostics into the error list, click error → jump to editor location.

## Scope

- `apps/ide/garin/builder.pas` — shell out to the compiler (posix exec/pipe via
  `lib/rtl`), stream stdout/stderr, parse `file:line:col: message` diagnostics
  into a render-agnostic error list.
- `apps/ide/garin/project.pas` — project model (files, main unit, build flags).
- Eliah: output pane shows live build log; error list pane; double-click a
  diagnostic → focus editor at file:line:col. All inline, no modal.

## Acceptance

Build a sample project from inside Eliah; diagnostics populate the error list;
clicking one navigates the editor. Self-host compiler not rebuilt (Track B).

## Log
- 2026-06-22 — filed (depends on M0).
- 2026-06-23 — core acceptance MET. garin/builder.TDiagList parses compiler
  output into a render-agnostic line+message list (gate: 62/62). Eliah shows an
  error-list pane under the project tree, populated on Compile; clicking a
  diagnostic jumps the editor caret to its line via a new PCL TMemo.CaretToLine
  (added gtk get_iter_at_line/place_cursor/get_insert/scroll_mark_onscreen).
  Remaining (lower priority): garin/project.pas project model (files / main unit
  / build flags), and column info (the compiler emits line only, no col).
