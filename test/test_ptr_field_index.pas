program test_ptr_field_index;
{ Indexing a pointer-typed class field, FField[i], used to return garbage:
  IRLowerAddress's pointer-index fast path only fired for an AN_IDENT base,
  so a field base fell through and indexed from &field with stride 8 instead
  of dereferencing the pointer. Fixed by an AN_FIELD pointer fast path that
  uses the field's value and its pointed-at element size. Covers read + write. }
type
  PInt = ^Integer;
  TC = class
  public
    Nums: PInt;
  end;
var
  c: TC;
  a: array[0..4] of Integer;
  i: Integer;
begin
  c := TC.Create;
  c.Nums := @a[0];
  for i := 0 to 4 do c.Nums[i] := (i + 1) * 10;   { write through ptr field }
  writeln(c.Nums[0]);   { 10 }
  writeln(c.Nums[2]);   { 30 }
  writeln(c.Nums[4]);   { 50 }
end.
