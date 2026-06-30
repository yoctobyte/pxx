# Inline loop variables — `for var i := 0 to N` / `for var x in coll` (Delphi 10.3 Rio)

- **Type:** feature (language / parser) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30
- **Origin:** carved out of the `--auto-locals` idea (feature-implicit-identifier-
  binding-strictness-switch) after a design pass. This is the **typed, standard,
  forward-compatible** layer; the sloppy layer is
  [[feature-implicit-locals-sloppy-switch]].

## Idea

Allow declaring the loop variable inline in the `for` header, matching Delphi
10.3 Rio's inline-variable syntax:

```pascal
for var i := 0 to N do ...        { i is a fresh loop-scoped Integer (inferred) }
for var i := N downto 0 do ...
for var x in coll do ...          { x's type inferred = the iterable's element type }
```

The type is **inferred**, not written — `for var i := 0` makes `i` an ordinal
from the bounds; `for var x in arr` makes `x` the element type. This is the same
inference pxx already does for the inline-`var`-statement form (below), just in
the loop header. `var` here plays the role of `auto`.

## Why

Eliminate the redundant separate `var i: Integer;` boilerplate for throwaway loop
counters — the single most common source of it. Forward-compatible: every
existing `for i := ...` with a pre-declared `i` keeps working unchanged; this only
adds a new spelling. Standard-ish (Delphi 10.3 set the precedent; pxx already
leans Delphi-compatible elsewhere).

## Already in place (most of the machinery)

- `tyAuto` (defs.inc:540, "statically typed variable with inferred type") + the
  inference path: an **inline `var x := expr` statement in a body already works**
  (`var s := 'abc'; writeln(s)` → `abc 3`; `var x := 7` → `7`). Gated on
  `EnableAutoVar` (default True; `--no-auto-var` disables). See parser.inc ~7512,
  ~7550 (the var-decl-with-init + auto-resolve), ~4223 ("use of auto variable
  before type is inferred").
- `for x in coll` over a dynarray/enum/iterable already works for a **pre-declared**
  `x`.

## Scope (the actual gap)

`ParseForStatementAST` (parser.inc ~6811) rejects `var` in the header
(`for: expected variable`). Teach it:

1. On `for`, if the next token is `var`, consume it, read the counter name, and
   **declare a loop-scoped local** for it instead of `FindSym`-ing an existing one.
   - Counted form (`:= a to b`): declare it ordinal (Integer, or inferred from the
     bound expression's type as the existing counter path does).
   - `in` form: declare it `tyAuto` and let the existing for-in element-type
     inference fill it (mirror the inline-`var := expr` resolve).
2. Scope: the inline counter is visible only in the loop body (Rio semantics).
   Simplest acceptable v1: a normal routine-local (function-scoped) like other
   pxx locals — loop-only scoping is a refinement, not a blocker.
3. Optionally accept an explicit type too (`for var i: Int64 := ...`) — cheap once
   the `var`-in-header path exists; skip if it complicates v1.

## Acceptance

- `for var i := 0 to N do` and `for var x in coll do` compile + run, `i`/`x`
  correctly typed; existing pre-declared `for` unchanged; `--no-auto-var` still
  compiles pre-declared loops (only the inline form is gated). Self-host
  byte-identical. Tests for counted + for-in inline forms.
