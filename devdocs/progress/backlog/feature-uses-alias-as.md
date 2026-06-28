# Support namespace aliasing in uses clauses (`uses 'name' as alias`)

- **Type:** feature
- **Status:** backlog
- **Track:** Pascal (Pascal compiler dialect)
- **Owner:** —
- **Opened:** 2026-06-28

## Motivation

Quoted unit names (such as `uses 'wayland-client';`) provide an escape hatch to import C headers containing non-identifier characters (like hyphens). However, referencing symbols from these units using fully-qualified names is syntactically invalid because `'wayland-client'.some_type` or `'wayland-client'.some_function` is not parseable by standard identifier rules.

Additionally, this provides a clean solution for **reserved keyword clashes** (such as `uses string;` resolving to `string.h`). Since `string` is a reserved Pascal keyword, it triggers compiler syntax errors. Aliasing allows importing it safely:
`uses 'string' as cstrings;` unblocking access like `cstrings.strlen(...)`.

Providing an alias mechanism (e.g. `uses 'wayland-client' as wayland;`) solves this:
1. It maps the compiled unit's namespace to a valid Pascal identifier (`wayland`).
2. It allows qualifiers like `wayland.some_type` or `wayland.some_function` to work cleanly.
3. It maps closely to similar import-aliasing constructs in Python (`import x as y`) or standard namespace imports.


## Scope

1. **Parser Integration**:
   - Update `ReadDottedUsesName` or `ParseUsesUnit` in `compiler/parser.inc` to recognize the `as <identifier>` suffix:
     `uses 'name' as alias;`
   - Store the mapping between the actual unit file name (`'name'`) and the scope's identifier name (`alias`) in the compiled unit metadata.
2. **Namespace Resolution**:
   - Ensure the symbol resolver looks up the alias identifier `alias` to find variables, types, and functions exported by unit `'name'`.

## Acceptance

- A program using `uses 'wayland-client' as wayland;` compiles successfully.
- Symbols from the unit are fully accessible both globally (unqualified) and qualified via `wayland.some_symbol`.

## Log
- 2026-06-28 — ticket opened.
