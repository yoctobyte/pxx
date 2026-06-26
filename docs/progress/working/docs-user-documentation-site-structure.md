# User documentation site structure and first content pass

- **Type:** docs
- **Track:** D
- **Status:** working
- **Owner:** Codex (Track D)
- **Opened:** 2026-06-26 (user documentation track)

## Goal

Create public-user Markdown documentation that can be imported by a website
without depending on the developer notes or progress tracker.

The documentation should use topic folders, not globally numbered files. The
root `index.md` is the canonical top-level ordering. Each topic folder may have
its own `index.md` to order chapters within that topic.

## Proposed shape

- `index.md` — top-level navigation and public documentation entry point.
- `install/` — requirements, install paths, platform notes, troubleshooting.
- `getting-started/` — first compile, first program, project layout, next steps.
- `language/` — Pascal basics, PXX dialect, FPC compatibility, units/packages.
- `features/` — user-visible compiler, library, tooling, and runtime features.
- `targets/` — native targets, cross targets, ESP32, cross-language interop.
- `reference/` — CLI, config, glossary, limits, compatibility tables.

## Acceptance

- A public docs root exists with a root `index.md` that defines the overall
  navigation order.
- Topic folders have local `index.md` files where chapter order matters.
- Existing useful user-facing material is linked, moved, or summarized without
  dragging in developer-only progress/history notes.
- Install, getting started, features, dialect, FPC compatibility, Pascal syntax,
  cross targets, and cross-language topics all have an obvious public home.
- Filenames are descriptive and stable; numbering is not required for ordering.

## Log

- 2026-06-26 — Ticket opened and claimed for Track D after deciding on
  topic-per-folder docs with root-index ordering.
- 2026-06-26 — Included progress-board usability in Track D scope: `check` should
  validate current board structure without blocking documentation work on old
  ticket hygiene debt.
- 2026-06-26 — Began public docs structure pass in `docs/site`: added topic
  folders for install, getting-started, features, targets, and reference, and
  added first-pass pages for Pascal basics, dialect, FPC compatibility, cross
  compilation, and cross-language notes.
