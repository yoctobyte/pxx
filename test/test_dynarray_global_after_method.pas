program test_dynarray_global_after_method;

{ Regression: AllocArray/AllocDynArray did not reset SymBlockId (and the other
  recycled parallel-array fields AllocVar resets). Symbol slots are reused after
  a proc body restores SymCount, so a dynamic-array GLOBAL declared after a
  method whose body contained a for-in (which allocates an anonymous index
  symbol into the now-recycled slot) inherited that slot's stale block id and
  became invisible to FindSym — `undefined variable` at the global's first use.
  Parity-sensitive on slot index, hence the deliberate var ordering here.

  Covers both the var-path for-in (`for v in g`) and a trailing dyn-array
  global declared after the method (`arr`). }

{$define PXX_MANAGED_STRING}

type
  TObj = class function Sum: Integer; end;

var g: array of Integer;

function TObj.Sum: Integer;
var v: Integer;
begin
  Result := 0;
  for v in g do Result := Result + v;
end;

var
  o: TObj;
  i, acc: Integer;
  arr: array of Integer;     { dyn-array global declared AFTER the method }
begin
  o := TObj.Create;
  SetLength(g, 2); g[0] := 3; g[1] := 4;
  Writeln(o.Sum);            { 7 }

  SetLength(arr, 3);
  arr[0] := 100; arr[1] := 20; arr[2] := 1;
  acc := 0;
  for i in arr do acc := acc + i;
  Writeln(acc);              { 121 }
end.
