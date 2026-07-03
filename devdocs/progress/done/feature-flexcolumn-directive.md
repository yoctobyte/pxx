# `flexcolumn` calling-convention directive

- **Type:** feature
- **Status:** done
- **Owner:** Track A
- **Opened:** 2026-06-06 (from todo.md §4)

## Motivation

The `value:w:d` formatting micro-grammar is today special-cased in
`write`/`writeln`/`Str`. Generalize it into a declarable calling-convention
directive so formatted routines can be ordinary library functions whose call
args carry optional `:w:d` modifiers. Pays off when variadic `write`/`writeln`
move to library code (see `feature-writeln-as-library`).

## Scope

- A declarable directive marking a routine as accepting per-arg `:w:d` modifiers.
- Spec the per-arg modifier → formal mapping and variadic interplay.
- Resolve in the **parser** (it knows the callee's directive) — never the lexer.

Rationale: `plan-pascal-syntax-issues.md` §B1.

## Acceptance

A library `write`-like routine declared with the directive accepts `x:w:d` call
syntax and formats correctly; existing `write`/`writeln`/`Str` unchanged.

## Spec (as implemented, 2026-07-03)

- Directive: `flexcolumn;` after a procedure/function header, in the same
  clause position as `overload`/`cdecl` (parser.inc header-directive loop).
  Stored as `ProcFlexColumn[procIdx]` (defs.inc), applied on all header
  resolution paths (register, forward/prescan, external).
- Call-site mapping: at a parenthesized call to a flexcolumn routine, each
  value argument may be followed by `:width[:decimals]`. Every value argument
  expands to **three** actuals — value, width, decimals — with defaults
  `0` / `-1` when a modifier is absent (write's defaults). The routine
  therefore declares `(v; w, d)` triples and normal arity/overload/type
  checking runs on the expanded list. Width/decimals are full expressions,
  not just integer literals (they bind real formals).
- Resolved entirely in the parser (`ParseFlexColumnTail`, hooked into the two
  general call-argument loops: expression-call and statement-call). The lexer
  is untouched; `write`/`writeln`/`Str` keep their existing special cases.
- Variadic interplay: `array of const` arguments are not expanded (a `[...]`
  literal contains no `:` grammar); flexcolumn is for fixed-arity routines.
  Don't mix flexcolumn and non-flexcolumn overloads of one name — the syntax
  is enabled from the first name match.

## Log
- 2026-06-06 — ticket opened from todo.md §4.
- 2026-06-28 — Removed `chore-inc-to-units` as a blocker after that refactor was
  rejected. This feature remains optional and should justify itself through a
  future library-backed formatted-output path, not through a broad compiler-file
  split.
- 2026-07-03 — Implemented (Track A). New `ProcFlexColumn` flag +
  `ParseFlexColumnTail` in the parser; regression `test/test_flexcolumn.pas`
  wired into `make test` (procedures, functions, multi-column, expression
  widths, defaults). Self-host byte-identical.
