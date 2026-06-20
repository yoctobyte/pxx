# Member access on a function-call result (`f(args).field`)

- **Type:** feature (compiler / parser + IR)
- **Status:** done
- **Owner:** Track A
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
- 2026-06-20 — Done (two layers — parser + IR). Parser: the postfix `.field` /
  `[i]` selector loop now continues after a call primary instead of stopping.
  New shared `ParseClassRecordSelectors(node, recId, var outTk)` walks the
  selectors on a class/record value node; applied to (a) function-call results
  via `ApplyCallResultPtrSuffix` (added a tyClass/tyRecord branch beside the
  existing pointer branch), (b) the bare implicit-Self method-call site in
  ParseFactor, and (c) the qualified instance-method-call site in ParseLValueAST
  — which was doing `Result := node; Exit` and is now `Continue` with
  `recName := ProcRetRecId[mpi]` (the static-method case already did this), so
  `obj.M(args).field`, `obj.M.field`, and chained `obj.M1.M2` all parse.
  IR: `IRLowerAddress` for `AN_FIELD` whose base is a **record**-returning
  `AN_CALL`/`AN_VIRTUAL_CALL` now uses `IRLowerAST(base)` — a record call's IR
  value is the address of its hidden aggregate-result temp (aggregates are
  by-reference, materialised by `IRAppendCall`) — instead of trying to take the
  address of a call node (which fell to IR_UNSUPPORTED). A class result was
  already a pointer value and worked. Repro prints `sword`; adventure past
  `engine.pas:446` AND `:462` (the latter was a record-call `.field` in
  `TGame.Move` reached once parsing advanced). Test
  `test/test_call_result_member.pas` (free fn, instance method, implicit-Self
  method; record + class results) wired into test-core + 3 cross suites.
  Gate green: `make test` byte-identical fixedpoint + `--threadsafe`; cross
  suites output-equal to x86-64; `make cross-bootstrap` byte-identical all 3.
- 2026-06-20 — Next adventure blocker filed as
  `lib-text-file-io-assign-rewrite` (`engine.pas:563`, `Assign(f, path)` — text
  file RTL). Library/Track-B, not a compiler bug. Method-call-ON-a-result
  (`f().Method(...)`) is still unsupported but not needed by adventure; the
  selector loop handles chained method calls through the `.` dispatch but a
  method call directly on a function-CALL primary in ParseFactor was not wired —
  note for a future ticket if a demo needs it.
- 2026-06-20 — commit reference (board checker): landed in bb94412
