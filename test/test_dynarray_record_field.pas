program test_dynarray_record_field;

{ bug-dynarray-in-record-corrupt: a dynamic-array field of a record must accept a
  whole-array assignment (rec.field := dynarrayvar), survive being passed through
  a var parameter, and round-trip through a by-value record return. The defect
  stored the source's slot address (truncated to the element width) into the
  field instead of the 8-byte handle -> segfault / garbage Length on the next
  access. The fix stores the handle at pointer width for a non-IDENT dyn-array
  lvalue. }

type
  TR = record n: Integer; a: array of Integer; end;

procedure Fill(var r: TR);              { assign a local dyn-array into a var-param field }
var loc: array of Integer; i: Integer;
begin
  SetLength(loc, 3);
  for i := 0 to 2 do loc[i] := (i + 1) * 10;
  r.n := 3;
  r.a := loc;
end;

function SumR(const r: TR): Integer;     { read the field back through a const-param }
var i, s: Integer;
begin
  s := 0;
  for i := 0 to r.n - 1 do s := s + r.a[i];
  Result := s;
end;

function MakeR: TR;                      { by-value record return with a dyn-array field }
var t: TR; i: Integer;
begin
  SetLength(t.a, 4);
  for i := 0 to 3 do t.a[i] := i + 1;
  t.n := 4;
  Result := t;
end;

var x, y: TR;
begin
  Fill(x);
  WriteLn('len=', Length(x.a), ' a0=', x.a[0], ' a2=', x.a[2], ' sum=', SumR(x));  { 3 10 30 60 }

  y := MakeR;
  WriteLn('ret len=', Length(y.a), ' first=', y.a[0], ' last=', y.a[3]);           { 4 1 4 }
end.
