program test_dynarray;

var
  a: array of Integer;
  b: array of Integer;
  i, sum: Integer;

procedure Check(ok: Boolean);
begin
  if ok then
    writeln(1)
  else
    writeln(0);
end;

begin
  { unallocated length is 0 }
  Check(Length(a) = 0);

  SetLength(a, 5);
  Check(Length(a) = 5);

  for i := 0 to 4 do
    a[i] := i * i;

  Check(a[0] = 0);
  Check(a[1] = 1);
  Check(a[4] = 16);

  sum := 0;
  for i := 0 to Length(a) - 1 do
    sum := sum + a[i];
  Check(sum = 30);

  { second independent dynamic array }
  SetLength(b, 3);
  b[0] := 100;
  b[1] := 200;
  b[2] := 300;
  Check(Length(b) = 3);
  Check(b[2] = 300);
  { a is unchanged by b }
  Check(a[4] = 16);

  { regrow a (fresh allocation, contents not preserved in v1) }
  SetLength(a, 10);
  Check(Length(a) = 10);
  a[9] := 42;
  Check(a[9] = 42);
end.
