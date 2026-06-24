# Eliah command surface (M5)

Eliah's designer and editor share **one selection model** and a small set of
**commands** that operate on it. The point: a command is the same whether a menu,
a toolbar button, a keyboard shortcut, or an AI agent issues it — they are
interchangeable *sources* feeding the same operations on `(selection, doc model,
code buffer)`. Nothing branches on "who asked" and nothing operates on layout
state.

## The shared selection model

`apps/ide/garin/selection.TSelectionModel` (render-agnostic, bochan-tested) holds
the current selection as a node index in the active form's doc model. The face
(`eliah.THandler.Sel`) routes every selection through it (`SelectNode`) and keeps
it in sync on each doc swap (open / undo / new). Both views read it:

- **Designer → editor** (`EditorToSelection`): selecting a node loads the design's
  `.lfm` into the editor and scrolls (`TMemo.CaretToLine`) to its `object <Name>`
  declaration. Keyed on the node `Name` (`docmodel` captures the `object <Name>:`
  identifier; `selection.LfmFindObjectLine` maps name → line).
- **Editor → designer** (`SelectFromEditorLine`): the `Link` toolbar command reads
  the editor caret line (`TMemo.CaretLine`), maps it to a component
  (`selection.LfmObjectNameAt` → `docmodel.FindByName`), and selects it.

## Commands

A command reads the current selection + doc + code buffer and mutates them. Each
is a plain `THandler` method; the toolbar button is just one binding.

| Command | Method | Effect |
|---------|--------|--------|
| Link (editor→designer) | `OnPickFromCaret` → `SelectFromEditorLine` | select the component under the editor caret |
| Wire OnClick | `OnWireOnClick` | assign the selection's `OnClick = <Name>Click` (round-trips in the `.lfm`, shows in the inspector) **and** generate the handler stub in the code editor (idempotent — `selection.CodeHasHandler` guards duplicates) |

The wire helpers (`EventHandlerName`, `EventHandlerStub`, `CodeHasHandler`) live in
`garin/selection` and are bochan-tested, so the codegen is verified headless and
any source (menu/shortcut/AI) gets identical results.

## Adding a command

1. Put the pure logic in `garin` (testable; no GTK), e.g. a text/doc transform.
2. Add a `THandler` method that reads `Sel.Selected` / `Dsn.Doc` / `Editor.Text`,
   calls the garin logic, `PushUndo` before mutating, then refreshes
   (`ShowInspector`, `DesignBox.Invalidate`).
3. Bind a source (toolbar `MkButton`, a `MkMenuItem`, or — later — the AI rail).

## AI rail (not yet built)

An AI agent is just another command source: it emits the same selection/command
ops over a console pane. It needs networking + a protocol, adds little to local
testing, and is deferred — see
`docs/progress/backlog/feature-eliah-ai-command-rail.md`.
