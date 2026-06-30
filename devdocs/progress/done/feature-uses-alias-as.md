# Support namespace aliasing in uses clauses (`uses 'name' as alias`)

- **Type:** feature
- **Status:** DONE (2026-06-30, Track A)
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

## Landed (2026-06-30, Track A)

`uses <name> as <alias>;` — `<name>` is any dotted/quoted unit name, `<alias>` a
plain identifier. Qualified access `alias.Sym` then resolves to the real unit's
symbols.

Key fact found while implementing: symbols are **unit-scoped** — each carries
`SymUnitIdx = CurrentUnitIdx` (the unit's `Strs[]` index), and a qualifier
`Unit.Sym` resolves via `FindProcInUnit/FindSymInUnit(name, qUnit)`. So the alias
must map to the **real unit's Strs[] index**, not its own — registering the alias
as a separate compiled-unit name (first attempt) made the qualifier *parse* but
the member lookup fail (`undefined variable`), because no symbol is tagged with
the alias's index.

Implementation:
- `ParseUsesEntry` (parser.inc) — new: reads the name, calls `ParseUsesUnit`,
  then on `as <ident>` records `alias_strIdx -> real_unit_strIdx` in a small table.
  Used at all three `uses` loops (program, unit interface, unit implementation).
- `UnitAliasName/UnitAliasReal/UnitAliasCount` table (defs.inc; reset in
  compiler.pas).
- `FindUnitOrAlias` (symtab.inc) — `FindCompiledUnit` then the alias table;
  `ConsumeUnitQualifier` now calls it, so a real unit name still wins over an alias
  of the same spelling.

Verified: `su.IntToStr(42)`, quoted `'classes' as cl` → `cl.TStringList.Create`,
unqualified access still works, comma-lists, missing-identifier error. Front-end
only (no codegen) → self-host **byte-identical**; `make test` green (new
`test/test_uses_alias.pas`).

**Note:** the motivating C-header cases (`uses 'wayland-client' as wayland`,
`uses 'string' as cstrings`) rely on the C-header import path actually compiling
the header and registering its symbols (Track C / crtl autopull); the aliasing
mechanism itself is target-agnostic and proven against RTL units here.
