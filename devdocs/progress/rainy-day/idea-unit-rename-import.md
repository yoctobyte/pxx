# `uses X as Y` unit-rename import (dialect extension)

- **Type:** idea
- **Status:** rainy-day 
- **Owner:** —
- **Opened:** 2026-06-06 (from todo.md §4)

## Motivation

A unit-rename import is missing. `uses X as Y` is **not** standard Pascal (that's
C#/Python `as`); Delphi has `uses U in 'file'` + dotted namespaces but no
rename-import. A rename would be a deliberate dialect extension.

## Open questions

- Is the ergonomic win worth a non-standard `uses` form?
- Interaction with qualified `UnitName.Symbol` lookup (already works).
- Syntax: `uses X as Y` vs something less Python-flavored.

## Frontend parity note (2026-06-18)

The same capability is missing on **both** frontends, and would land as one
feature if adopted:

- Pascal: no `uses X as Y` (idea only).
- Nil Python: `import X` works (rewritten to `uses`), but **`import X as Y`
  (alias) and `from X import Y` are not supported** — pyparser takes only
  `import name[, name]`.

There is **no `as`-for-import AST node anywhere**; `import`/`uses` just feed names
to the unit resolver. (Confirms the `as` token is free for the is/as type-cast —
the only other `as` is the contextual ident in `specialize ... as Name`.)

## Status

Idea only — decide whether to adopt before scoping. Not standard; no current
source needs it. If adopted, cover both the Pascal `uses` and Python `import`
forms together.

## Log
- 2026-06-06 — ticket opened from todo.md §4.
- 2026-06-18 — recorded Python `import as` is the same missing capability; no
  import-alias AST node exists on either frontend.
