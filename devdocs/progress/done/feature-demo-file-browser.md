# Flagship Demo — Midnight Commander-like TUI file browser (libc-free)

- **Type:** feature
- **Status:** done
- **Owner:** — (lock released; last worked by Codex)
- **Opened:** 2026-06-21
- **Relation:** Sibling to other flagship demos. **Depends on** the low-level directory scanning in feature-sys-getdents and unbuffered terminal input in feature-rtl-terminal-raw-mode.

## Goal

An interactive terminal file manager (`examples/fm/`) supporting multiple pane layouts (1, 2, 3, or 4 active panes) and GUI-style tile view modes with live true-color previews (text and PNG thumbnails) using ansirender's quadrant-plus-detail engine.

## Specification

- **Panes**: Divide terminal columns equally among active panes. Switch focus via `Tab` / `Shift-Tab`.
- **View Modes**:
  - `compact`: name, size, optional modification date.
  - `tile`: tiles containing names and a live preview card.
- **Preview Card Engine**:
  - Text files: Display the first 10 lines.
  - PNG files: Render a thumbnail using the true-color quadrant-plus-detail engine.
  - Unsupported files: Display a colored placeholder icon indicating file format type.
- **Controls**: Interactive shortcut keys (e.g. `F1`..`F4` to adjust pane counts, `Enter` to navigate folders, Arrow keys to scroll).

## Log
- 2026-06-21 — Opened.
- 2026-06-21 — First source slice in progress: `examples/fm/fm.pas` lists one
  or two terminal panes using `SysUtils.GetDirectoryContents` and ANSI rendering.
  Current slice is non-interactive and shows names/type only; stat metadata,
  previews, and raw-key navigation remain in this ticket or its library
  blockers.

- 2026-06-21 — HALTED → `unfinished/`. `working/` lock released (no active agent). First demo slice committed as 9d4a162 (examples/fm/fm.pas); needs stat metadata, previews, raw-key nav.
- 2026-06-22 — DONE in this commit. Expanded `examples/fm/fm.pas` into a
  one-shot/interactive terminal browser with 1-4 panes, compact/tile modes,
  stat-backed size display, raw-key controls (`--interactive`), text previews,
  PNG thumbnails through `PngDecodeRGBA` + `RenderAnsiTrueColorQuadrant`, and
  colored placeholders for other file types. The default render remains
  one-shot for deterministic smoke. Verified direct compile/run in compact and
  tile mode plus `make demos`.
