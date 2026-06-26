# `Length` on implicit-`Self` dynamic-array field fails in methods

- **Type:** bug (compiler / resolver)
- **Status:** done
- **Owner:** Track A
- **Opened:** 2026-06-20 (demo dashboard against pinned v14)
- **Relation:** blocks `examples/adventure`; related to dynamic-array field
  support, which works when the field is explicitly qualified as `Self.Field`.

## Symptom

`examples/adventure/adventure.pas` fails while compiling `engine.pas`:

```text
pascal26:325: error: Length: undefined variable ()
```

The failing method code is:

```pascal
function TMonster.Fight(const guess: AnsiString): Boolean;
begin
  if (CurIdx < 0) or (CurIdx >= Length(Riddles)) then begin Result := True; Exit; end;
  Result := LowerStr(Trim(guess)) = LowerStr(Trim(Riddles[CurIdx].A));
end;
```

`Riddles` is a dynamic-array field of `TMonster`. The same shape works when
qualified as `Self.Riddles`.

Minimal repro:

```pascal
program implicit_dynfield;
type
  TObj = class
    Items: array of Integer;
    function N: Integer;
  end;

function TObj.N: Integer;
begin
  Result := Length(Items);
end;

var o: TObj;
begin
  o := TObj.Create;
  SetLength(o.Items, 2);
  Writeln(o.N);
end.
```

Pinned v14 errors at `Length(Items)`. Changing it to `Length(Self.Items)`
compiles and prints `2`.

## Direction

The normal implicit-field resolver is good enough for scalar field use in
methods, but the `Length` classifier / dynamic-array handling does not preserve
the implicit-`Self` field shape. Route unqualified class fields through the same
field-address path used by `Self.Field`.

## Acceptance

- The minimal repro prints `2`.
- `examples/adventure/adventure.pas` gets past the current line-325 blocker.
- Existing `test/test_dynarray_field.pas` stays green.

## Log
- 2026-06-20 — Opened after `make demos` on pinned v14 failed on adventure.
- 2026-06-20 — Fixed. Root cause was narrower than the direction note: the
  shared `ParseLValueAST` *already* resolves an implicit-`Self` field when its
  `idx` arg is `<0` (parser.inc ~957–985) and errors itself
  ('undefined variable') when the name is truly unknown. The `Length` and
  `High` intrinsics each carried a redundant trailing
  `if idx < 0 then Error('… undefined variable')` *after* calling
  `ParseLValueAST` — so they rejected a field that had just resolved
  successfully. `SetLength` had no such guard, so it was already correct (the
  ticket's `SetLength(o.Items, …)` repro was qualified, masking that). Fix =
  drop the two redundant guards. Repro now prints `2` (and `1` for `High`).
  Added `test/test_method_implicit_field.pas` (Length/SetLength/High over an
  implicit-`Self` dyn-array field + a scalar-field regression), wired into
  test-core + the i386/aarch64/arm32 cross suites. Gate green: `make test`
  byte-identical fixedpoint + `--threadsafe`; all 3 cross suites output-equal to
  x86-64; `make cross-bootstrap` byte-identical on all 3.
- 2026-06-20 — Follow-on discovery filed as `bug-for-in-implicit-self-field`:
  `for x in <field>` (implicit `Self`) is the *next* adventure blocker
  (`engine.pas:349`). Same family but a deeper fix (`ParseForInVarAST` is keyed
  on a symbol index, not an AST node), so kept as a separate ticket.
- 2026-06-20 — commit reference (board checker): landed in bf317ff
