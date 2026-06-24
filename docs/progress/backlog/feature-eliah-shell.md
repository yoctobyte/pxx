# feature: Eliah shell — perspective-based IDE (one window, splitter-tree layout)

- **Type:** feature (epic / Track B)
- **Status:** backlog
- **Track:** B
- **Parent:** feature-eliah-ide
- **Opened:** 2026-06-23

## Vision

Eliah is **one window**. No floating palettes/inspectors/forms — that soup is the
Delphi/Lazarus lesson we refuse to repeat. The window is a **tree of splitters**
(nested `TPaned`); every visible thing (file tree, editor, console, form preview,
object inspector, palette) is a **leaf pane** in that tree.

"Code editor", "GUI designer", and "Split" are **not modes in the code** — they
are three saved **layout descriptors (perspectives)**. Switching mode reflows the
same panes; it never opens a window and never branches app logic.

### The one rule (do not violate)

**Mode = pure layout.** The document workspace, project model, selection, and doc
model are mode-independent. The moment `if DesignMode then …` leaks into logic,
we have rebuilt Lazarus. A perspective only decides which panes are visible and
how the splitter tree is arranged.

## Principles (carried into every milestone)

- **Splitter tree, not flat.** Window = binary tree of H/V `TPaned`; leaves are
  pane containers. A perspective = serialized tree + ratios.
- **Leaf = slot, not view.** A leaf holds one view today, a tab strip later.
  Build the slot abstraction now so tabs are an upgrade, not a rewrite.
- **Collapse ≠ destroy.** Dragging/▾ a pane to its edge collapses it to a thin
  clickable strip that remembers its last ratio.
- **Compacting is priority + min, not magic.** Panes carry a min-size and a
  priority. Distribute by ratio, clamp to min; when the window can't satisfy the
  sum of mins, auto-collapse the lowest-priority pane. Predictable > pretty.
- **Components are a registry.** Visual widgets and non-visual libraries are the
  same thing: a registered `TComponent` with published RTTI. The palette lists
  `RegisterClass`'d components; non-visual ones live in a tray.
- **Selection is a shared, bidirectional event.** Designer↔editor link, and any
  future AI command, ride one selection/command model — never special layout.

## Milestones — M1–M5 DONE (2026-06-24)

1. ✅ `done/feature-eliah-layout-tree` — window → nested-`TPaned` tree.
2. ✅ `done/feature-eliah-pane-collapse` (core) — full collapse/restore + View
   toggles. DEFERRED sub-item: the labelled clickable collapse *strip* + per-pane
   chevron (needed a stacking container; now UNBLOCKED — `done/
   bug-widgetset-virtual-arg-corruption` cleared the TWidgetSet-virtual block, so
   the strip widget can be built).
3. ✅ `done/feature-eliah-perspectives` — Code/Design/Split presets + compacting.
4. ✅ `done/feature-eliah-component-palette` — registry palette (visual + non-visual
   tray) + RTTI inspector, on the `TComponent`/`Create(AOwner)` model.
5. ✅ `done/feature-eliah-selection-link` — shared bidirectional selection link
   (designer↔editor) + wire-OnClick command; the rail AI tooling will ride
   (`backlog/feature-eliah-ai-command-rail`).

All five milestones are complete; only the M2 collapse-strip/chevron polish is
deferred (now unblocked). The shell is registry-driven with a shared
selection/command surface.

## Future (not yet ticketed)

- Tabs inside a leaf pane (the slot upgrade).
- AI tooling as a console pane + commands over the doc model ("link button click
  to …") — rides milestone 5's selection/command model, no layout special-case.

## Related

- `done/feature-eliah-pane-reflow` (basic resize) is superseded by milestone 1.
- `unfinished/feature-eliah-from-lfm` (stream Eliah's own layout) and
  `urgent/bug-metaclass-new-getclass-vmt` are orthogonal but converge: once the
  shell is data-driven, the layout itself can be a streamed/serialized form.

## Log
- 2026-06-23 — filed (epic) after the layout design discussion.
