program test_forin_implicit_field;

{ `for x in Field` over an implicit-Self array/string field inside a method,
  mirroring how `for x in Self.Field` resolves. Regression for the bug where an
  unqualified field for-in source errored 'not a generator, enum type, or
  iterable variable' because FindSym only sees locals/globals. Covers a
  dynamic-array field, a record-element dyn-array field, and a string field.
  The plain-variable for-in path is exercised too so the shared loop-builder
  refactor stays correct for the non-field case. }

{$define PXX_MANAGED_STRING}

type
  TPair = record A, B: Integer; end;

  TObj = class
    Nums: array of Integer;
    Pairs: array of TPair;
    Tag: AnsiString;
    function SumNums: Integer;
    function SumPairs: Integer;
    function CountUpper: Integer;
  end;

function TObj.SumNums: Integer;     { dyn-array-of-ordinal field }
var v: Integer;
begin
  Result := 0;
  for v in Nums do Result := Result + v;
end;

function TObj.SumPairs: Integer;    { dyn-array-of-record field }
var p: TPair;
begin
  Result := 0;
  for p in Pairs do Result := Result + p.A + p.B;
end;

function TObj.CountUpper: Integer;  { string field, char iteration }
var c: Char;
begin
  Result := 0;
  for c in Tag do
    if (c >= 'A') and (c <= 'Z') then Result := Result + 1;
end;

var
  { NOTE: `arr` is declared before the scalars on purpose. A pre-existing
    latent symbol-table bug (filed as bug-forin-in-method-global-var-corruption)
    corrupts a dyn-array global declared *after* other globals when a method
    body contains a for-in; declaring it first sidesteps that unrelated bug so
    this test isolates the implicit-Self-field feature. }
  arr: array of Integer;
  o: TObj;
  i, acc: Integer;
begin
  o := TObj.Create;
  SetLength(o.Nums, 4);
  o.Nums[0] := 1; o.Nums[1] := 2; o.Nums[2] := 3; o.Nums[3] := 4;
  SetLength(o.Pairs, 2);
  o.Pairs[0].A := 10; o.Pairs[0].B := 20;
  o.Pairs[1].A := 5;  o.Pairs[1].B := 7;
  o.Tag := 'aBcDeF';

  Writeln(o.SumNums);     { 10 }
  Writeln(o.SumPairs);    { 42 }
  Writeln(o.CountUpper);  { 3 }

  { plain-variable for-in regression (symbol path through the same builder) }
  SetLength(arr, 3);
  arr[0] := 100; arr[1] := 20; arr[2] := 1;
  acc := 0;
  for i in arr do acc := acc + i;
  Writeln(acc);           { 121 }
end.
