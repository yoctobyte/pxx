# Member access on a function-call result (`f(args).field`)

- **Type:** feature (compiler / parser)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-20 (next `examples/adventure` blocker after for-in
  member-access source landed)
- **Relation:** the current `examples/adventure` blocker (`engine.pas:446`).
  Independent of for-in.

## Symptom

`examples/adventure/engine.pas:446` cannot compile:

```pascal
WriteLn(Col('  The way ' + DirName(d) + ' is sealed. You lack ' +
            CatalogItem(key).Name + '.', YEL));
```

```text
pascal26:446: error: expected comma or close parenthesis
```

The offending sub-expression is `CatalogItem(key).Name` — a `.field` (or
method) access applied directly to the *result* of a function call, where the
function returns a class/record.

Minimal repro:

```pascal
program callresult_member;
type TItem = class Name: AnsiString; end;
function MakeItem: TItem;
begin Result := TItem.Create; Result.Name := 'sword'; end;
begin
  Writeln(MakeItem.Name);   { or MakeItem().Name — error: expected comma or ')' }
end.
```

## Direction

The expression/postfix parser handles `ident.field`, `ident[i].field`, etc., but
does not continue parsing `.field` / `[i]` / `^` selectors after a function-call
primary `f(args)`. After building the AN_CALL node for the call, the selector
loop should run on it (the call result's record type is available via
`ProcRetRecId`, already used by `ResolveNodeRec` for `AN_CALL`). Apply in both
the factor/expression path and `ParseLValueAST` so `f().field := x` works too.

## Acceptance

- The minimal repro prints `sword`.
- `examples/adventure` gets past `engine.pas:446`.
- Tests for call-result `.field` read (and ideally a method call + a field
  store) in test-core.

## Log
- 2026-06-20 — Opened. Surfaced immediately after
  `feature-forin-member-access-source` unblocked `engine.pas:368`; the next
  adventure line (`446`, `CatalogItem(key).Name`) needs call-result member
  access.
