# Import C headers for complex libraries (glib/GTK-grade)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-06 (from todo.md §2c — "the real goal")

## Motivation

Hand-written `external 'soname'` bindings (e.g. `test/gui/gtk3.pas`) hardcode the
soname and every prototype → manual versioning and drift. End state: `uses gtk;`
resolves `/usr/include/gtk-3.0/...` and derives the soname from the headers, like
`ctype` already does. Manual `external` stays as the escape hatch.

## Scope (remaining stages)

Plan: `../../developer/plan-c-header-import.md`. Stage A/B + float ABI + arg
spill done. Remaining:

- Stage C — macro soup: nested includes, function-like macros, `##` token paste,
  `#` stringification, variadic macros, attribute spellings, conditional platform
  blocks, typedef/struct/enum/pointer churn.
- Stage D — recovery; Stage E — final wiring (`uses gtk;`).
- Related C-interop gaps: struct-by-value ABI proof, out-param depth ≥ 2 beyond
  the strict trailing lift, non-integer `#define` constants, deeper callback
  signature metadata.

## Acceptance

A stock GTK3 header set imports and a GTK program builds without a hand-written
binding unit; existing simple-header imports stay green. Keep hot-path lookups
O(1) (see AGENTS.md FindCTag landmine).

## Log
- 2026-06-06 — ticket opened from todo.md §2c.
