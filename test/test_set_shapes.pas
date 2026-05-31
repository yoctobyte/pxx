program test_set_shapes;

type
  TByteSet = set of Byte;
  TRec = record
    Values: TByteSet;
  end;

procedure CheckValue(s: TByteSet);
begin
  if (1 in s) and (9 in s) then writeln(1) else writeln(0);
end;

procedure AddNine(var s: TByteSet);
begin
  s := s + [9];
end;

procedure Run;
var
  a, b: TByteSet;
  r: TRec;
begin
  a := [1, 2];
  b := a + [3];
  r.Values := b;
  if 3 in r.Values then writeln(1) else writeln(0);
  AddNine(r.Values);
  if 9 in r.Values then writeln(1) else writeln(0);
  CheckValue(r.Values);
end;

begin
  Run;
end.
