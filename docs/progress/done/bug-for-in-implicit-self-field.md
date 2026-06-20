# `for-in` over an implicit-`Self` array field fails in methods

- **Type:** bug (compiler / resolver)
- **Status:** done
- **Owner:** Track A
- **Opened:** 2026-06-20 (found while fixing `bug-implicit-self-dynarray-length`)
- **Relation:** same family as the now-fixed `Length`/`SetLength`/`High`
  implicit-`Self` field bug; the next blocker in `examples/adventure`
  (`engine.pas:349`) after that fix.

## Symptom

`examples/adventure/adventure.pas` now compiles past the old line-325
(`Length(Riddles)`) blocker but fails at `engine.pas:349`:

```text
pascal26:349: error: for-in: not a generator, enum type, or iterable variable ()
```

The failing code iterates an unqualified class field:

```pascal
function TGame.FindRoom(const id: AnsiString): TRoom;
var r: TRoom;
begin
  Result := nil;
  for r in Rooms do          { Rooms is a dyn-array field of TGame }
    if r.Id = id then begin Result := r; Exit; end;
end;
```

`for r in Self.Rooms` is expected to work; `for r in Rooms` does not.

Minimal repro:

```pascal
program forin_implicit_field;
type
  TObj = class
    Items: array of Integer;
    function Sum: Integer;
  end;

function TObj.Sum: Integer;
var v: Integer;
begin
  Result := 0;
  for v in Items do Result := Result + v;
end;

var o: TObj;
begin
  o := TObj.Create;
  SetLength(o.Items, 3);
  o.Items[0] := 10; o.Items[1] := 20; o.Items[2] := 12;
  Writeln(o.Sum);   { expected 42 }
end.
```

## Root cause

`ParseForStatementAST` (compiler/parser.inc, the iterable-variable branch
~4786) resolves the source with `fsym := FindSym(CurTok.SVal)` — locals/globals
only — then calls `ParseForInVarAST(varIdx, fsym)`, which is keyed on a *symbol
index*, not an AST node. When the name is an implicit-`Self` field, `FindSym`
returns `<0`, so it falls through to the
`'for-in: not a generator, enum type, or iterable variable'` error.

This is the same gap the `Length`/`High` intrinsics had, but the fix is more
involved: `ParseForInVarAST` takes a symbol, not a node, so supporting an
implicit-`Self` (or any `obj.field`) source needs a node-based source variant
(build the `AN_FIELD` over `Self` via the same path `ParseLValueAST` uses, then
drive the enumerator desugar off that node).

## Acceptance

- The minimal repro prints `42`.
- `examples/adventure` gets past `engine.pas:349`.
- Existing for-in tests stay green; add an implicit-`Self`-field for-in test to
  test-core + the i386/aarch64/arm32 cross suites.

## Log
- 2026-06-20 — Opened. Discovered immediately after
  `bug-implicit-self-dynarray-length` landed (that fix covered Length/SetLength/High).
- 2026-06-20 — Fixed. Refactored the for-in array/string desugar to be
  container-*node* based: new `GenMakeContainerNode` (rebuilds a fresh symbol
  ident or `AN_FIELD`-over-Self per use, so the Length bound and the element
  access don't alias one node — codegen walks a tree, not a DAG) +
  `GenMakeLengthCallNode` + a shared `BuildForInArrayLoop`. `ParseForInVarAST`
  now feeds that builder via the symbol path; new `ParseForInFieldAST` feeds it
  via an implicit-Self field (metadata read from the `UFld…` tables instead of
  `Syms[…]`). `ParseForStatementAST` resolves an unqualified field after FindSym
  misses — guarded to only the *bare* field case (next token = `do`) so
  qualified `obj.field` sources aren't mis-grabbed. Repro prints `42`; adventure
  now past `engine.pas:349`. Test `test/test_forin_implicit_field.pas`
  (dyn-array-of-ordinal, dyn-array-of-record, string field + a plain-var
  regression) wired into test-core + the 3 cross suites. Gate green: `make test`
  byte-identical fixedpoint + `--threadsafe`; cross suites output-equal to
  x86-64; `make cross-bootstrap` byte-identical on all 3.
- 2026-06-20 — Two follow-ons filed: (1) `feature-forin-member-access-source` —
  the *next* adventure blocker (`engine.pas:368`, `for it in Player.Inventory`)
  needs a qualified-member-access for-in source, a broader change (node→array
  metadata classifier). (2) `bug-forin-in-method-global-var-corruption` — a
  pre-existing latent symbol-table bug (confirmed on the HEAD compiler before
  this change) where a method-body for-in plus a trailing dyn-array global
  corrupts that global's registration; this test orders its globals to dodge it.
