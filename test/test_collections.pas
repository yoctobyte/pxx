program test_collections;

{ The generic list library (lib/rtl/collections.pas) specialized for two very
  different element types from a single template: a scalar Integer list and a
  managed-AnsiString list. Exercises cross-unit generic specialization, chunked
  growth across several reallocations, indexed get/put, count, clear, and the
  managed-string retain/release on store. }

{$define PXX_MANAGED_STRING}

uses collections;

type
  TIntList = specialize TList<Integer>;
  TStrList = specialize TList<AnsiString>;

var
  ints: TIntList;
  strs: TStrList;
  i, sum: Integer;
begin
  ints := TIntList.Create;
  for i := 0 to 99 do ints.Add(i * i);
  writeln(ints.Count);          { 100 }
  writeln(ints.Get(0));         { 0 }
  writeln(ints.Get(9));         { 81 }
  writeln(ints.Get(99));        { 9801 }
  ints.Put(9, 7);
  writeln(ints.Get(9));         { 7 }
  sum := 0;
  for i := 0 to ints.Count - 1 do sum := sum + ints.Get(i);
  writeln(sum);                 { 328276 = sum of squares 0..99 (328350) - 81 + 7 }
  ints.Clear;
  writeln(ints.Count);          { 0 }

  strs := TStrList.Create;
  strs.Add('alpha');
  strs.Add('beta');
  strs.Add('gamma');
  writeln(strs.Count);          { 3 }
  writeln(strs.Get(0));         { alpha }
  writeln(strs.Get(2));         { gamma }
  strs.Put(1, 'BETA');
  writeln(strs.Get(1));         { BETA }
end.
