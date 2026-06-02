program test_static_array_ansistring_field;

{ Regression: indexing a static array of managed AnsiString — standalone, as a
  record field, and as a field of a record stored in a dynamic array. All three
  previously mis-lowered the element address (treating the array as a scalar
  AnsiString) and segfaulted. }

{$define PXX_MANAGED_STRING}

type
  TEntry = record
    Tags: array[0..1] of AnsiString;
    Id: Integer;
  end;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

var
  t: array[0..1] of AnsiString;
  e: TEntry;
  a: array of TEntry;

begin
  { Standalone static array of AnsiString. }
  t[0] := 'aa';
  t[1] := 'bb';
  Check(t[0] = 'aa');
  Check(t[1] = 'bb');

  { Static AnsiString array as a record field. }
  e.Id := 99;
  e.Tags[0] := 'tag0';
  e.Tags[1] := 'tag1';
  Check(e.Tags[0] = 'tag0');
  Check(e.Tags[1] = 'tag1');
  Check(e.Id = 99);

  { Static AnsiString array field of a record inside a dynamic array. }
  SetLength(a, 1);
  a[0].Id := 7;
  a[0].Tags[0] := 'dyn0';
  a[0].Tags[1] := 'dyn1';
  Check(a[0].Tags[0] = 'dyn0');
  Check(a[0].Tags[1] = 'dyn1');
  Check(a[0].Id = 7);
end.
