# `for-in` over a qualified member-access source (`obj.field`, `Self.field`)

- **Type:** feature (compiler / parser)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-20 (next `examples/adventure` blocker after for-in
  implicit-Self field landed)
- **Relation:** generalizes `bug-for-in-implicit-self-field` (which handled the
  *bare* unqualified field case). The current `examples/adventure` blocker.

## Symptom

`examples/adventure/engine.pas:368` cannot compile:

```pascal
function TGame.Has(const id: AnsiString): Boolean;
var it: TItem;
begin
  Result := False;
  for it in Player.Inventory do      { Player is a field; Inventory a dyn array }
    if it.Id = id then begin Result := True; Exit; end;
end;
```

```text
pascal26:368: error: for-in: not a generator, enum type, or iterable variable
```

`for x in <single identifier>` works (local/global var, enum type, generator,
implicit-Self field). A *qualified* source — `obj.field`, `Self.field`,
`a.b.c`, or any postfix lvalue expression — does not.

## Root cause

`ParseForStatementAST` (compiler/parser.inc) only inspects a single identifier
token after `in` (FindProc / FindEnumType / FindSym / implicit-Self field),
each keyed on a name. It never parses a general postfix lvalue. After `Player`
the next token is `.`, none of the single-name lookups match, and it errors.

## Direction

Parse the for-in source as a postfix lvalue expression (the same machinery as a
factor / `ParseLValueAST`) producing a container **node**, then drive the
existing node-based `BuildForInArrayLoop` off it. The loop builder already
accepts an arbitrary container node (added for the implicit-Self-field fix); the
missing piece is deriving the container's array/string metadata (is-array,
element type, dyn-vs-static, length source) from an arbitrary expression node
rather than a `Syms[...]` / `UFld...` table entry. A node→element-type/array
classifier is the real work here.

## Acceptance

- `for x in obj.field` and `for x in Self.field` iterate correctly.
- `examples/adventure` gets past `engine.pas:368`.
- Tests (member-access for-in, dyn-array and string) in test-core + cross suites.

## Log
- 2026-06-20 — Opened. The bare implicit-Self-field for-in
  (`bug-for-in-implicit-self-field`) landed and unblocked `engine.pas:349`; the
  next adventure line (`368`, `Player.Inventory`) needs this broader form.
