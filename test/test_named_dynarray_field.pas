program test_named_dynarray_field;

{ A class/record field whose type is a NAMED dynamic-array alias (TIntArray =
  array of Integer) must behave as a real dynamic array: SetLength, indexing and
  Length all work. Regression for the VM-library miscompile where SetLength on a
  named-alias dyn-array field was misrouted to the string-SetLength codegen path
  ("SetLength expects a string variable in IR codegen"). The fix records the
  field's dyn-array depth from the array-type alias (ArrTypeIsDyn/DynDepth). }

type
  TIntArray = array of Integer;
  TStrArray = array of AnsiString;

  TBag = class
    Nums: TIntArray;
    Names: TStrArray;
    procedure Fill;
  end;

  TRec = record
    Vals: TIntArray;
  end;

procedure TBag.Fill;
begin
  SetLength(Self.Nums, 3);
  Self.Nums[0] := 10; Self.Nums[1] := 20; Self.Nums[2] := 30;
  SetLength(Self.Names, 2);
  Self.Names[0] := 'a'; Self.Names[1] := 'bb';
end;

var
  b: TBag;
  r: TRec;
  i, sum: Integer;
begin
  b := TBag.Create;
  b.Fill;
  sum := 0;
  for i := 0 to Length(b.Nums) - 1 do sum := sum + b.Nums[i];
  WriteLn('nums len=', Length(b.Nums), ' sum=', sum);          { 3 60 }
  WriteLn('names len=', Length(b.Names), ' ', b.Names[0], b.Names[1]);  { 2 abb }

  SetLength(r.Vals, 4);
  r.Vals[3] := 99;
  WriteLn('rec len=', Length(r.Vals), ' v3=', r.Vals[3]);      { 4 99 }
end.
