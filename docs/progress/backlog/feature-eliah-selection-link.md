# feature: Eliah shared selection model — designer ↔ editor link (+ AI rail)

- **Type:** feature (Track B)
- **Status:** backlog
- **Track:** B
- **Parent:** feature-eliah-shell
- **Opened:** 2026-06-23

## Goal

One **shared, bidirectional selection/command model** wired across the designer
and the editor. Selecting a component anywhere highlights it everywhere; commands
(rename, wire event, and future AI actions) operate on this model, never on
layout state.

## Why

The thing Delphi/Lazarus did *adequately* and is the real IDE value. Make it
first-class and explicit so it stays clean and so AI tooling has a rail to ride.

## Scope

- **Selection model** (render-agnostic, in garin): "current selection" = a set of
  component ids in the active form's doc model, with change events.
- **Designer → editor**: selecting a widget in the designer scrolls/highlights its
  creation + event-handler code in the editor.
- **Editor → designer**: placing the caret on a component identifier selects that
  component in the designer.
- **Command surface**: actions take the selection (e.g. "wire OnClick" generates a
  handler stub + assigns it; "rename" updates code + .lfm + doc model together).
- **AI rail (stub only here)**: AI tooling is a *command source* + a console pane,
  emitting the same commands ("link button click to SaveFile"). No layout or
  mode special-casing — it operates on selection + doc model like any command.

## Acceptance

Designer selection moves the editor caret to the matching code and vice-versa; at
least one command (wire OnClick stub) works end-to-end through the selection
model; the command surface is documented so AI/menus/shortcuts are
interchangeable sources. `gui_suite` + garin green (selection model unit-tested
headless via bochan); screenshot of linked selection.

## Notes

- Keep the selection model in `apps/ide/garin` (render-agnostic, bochan-testable),
  faces (eliah/ilja) subscribe.
- Event-handler wiring touches code generation; reuse `garin/lfmload` +
  `buffer`/editor mutation. Mind the streamer/RTTI path.

## Log
- 2026-06-23 — filed (milestone 5 of feature-eliah-shell).

## Progress 2026-06-24 — shared model + bidirectional link landed

Foundation (commit a74c646, garin, bochan-tested):
- docmodel node Name (the `object <Name>:` identifier) — captured + emitted by
  lfmload (was discarded); FindByName.
- garin/selection.TSelectionModel: shared current selection (index) +
  Select/SelectByName/Clear/SelectedName/change-count.
- selection.LfmFindObjectLine / LfmObjectNameAt: component name <-> .lfm line.

Wiring (commit 1ce2032, eliah + lib/pcl):
- THandler.Sel routes all selections through the model (synced on doc swap).
- **Designer -> editor**: select a node -> editor loads the design .lfm + scrolls
  (TMemo.CaretToLine) to its `object <Name>` line.
- **Editor -> designer**: 'Link' toolbar button reads the caret line (new
  TMemo.CaretLine + TWidgetSet.MemoCaretLine virtual + gtk get_iter_at_mark/
  iter_get_line bindings) and selects the component declared there.
- The 'Link' button is one command source on the shared model — menus/shortcuts/AI
  are interchangeable sources.

Gates: garin 157/157, eliah --smoke OK (both directions, deterministic via
SelectFromEditorLine), gui_suite OK, screenshot shows the Link button.

### Remaining (keeps this ticket open)
- **wire-OnClick command**: generate a handler stub + assignment (touches .pas
  codegen); the example end-to-end command from the acceptance.
- **AI rail + console pane** (stub): an AI command source emitting the same
  selection/command ops; no layout special-casing.
- **Command-surface doc**: short note so AI/menus/shortcuts are documented as
  interchangeable sources.
- **Editor->designer on caret move** (not just the button): wants a TMemo caret/
  click signal; the button covers it for now.
- Link currently keys on the .lfm object declaration (the box-emulation creation
  site); .pas event-handler navigation arrives with wire-OnClick.
