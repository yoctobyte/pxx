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

  { grow preserves old contents and zero-initializes new slots }
  SetLength(a, 10);
  Check(Length(a) = 10);
  Check(a[1] = 1);
  Check(a[4] = 16);
  Check(a[5] = 0);
  a[9] := 42;
  Check(a[9] = 42);

  { shrink preserves the retained prefix }
  SetLength(a, 2);
  Check(Length(a) = 2);
  Check(a[1] = 1);

  { zero length publishes nil; a later allocation starts zeroed }
  SetLength(a, 0);
  Check(Length(a) = 0);
  SetLength(a, 4);
  Check(Length(a) = 4);
  Check(a[0] = 0);
  Check(a[3] = 0);

  { assignment ALIASES — one array, two names — and only a RESIZE detaches.
    This block asserted copy-on-write ("shares storage until either variable is
    written") until 2026-08-06; that was x86-64's alone and is gone. Every value
    below is what an FPC build of the same sequence prints
    (bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing). }
  a[0] := 77;
  b := a;
  Check(b[0] = 77);
  b[0] := 88;
  Check(a[0] = 88);        { shared: the write through B reaches A }
  Check(b[0] = 88);
  b := a;
  SetLength(b, 6);         { resize DETACHES b, carrying the current values }
  Check(Length(b) = 6);
  Check(b[0] = 88);
  b[0] := 99;
  Check(a[0] = 88);        { independent now, so A keeps its own value }
  Check(b[0] = 99);
  SetLength(a, 0);
  Check(b[0] = 99);        { and B survives A being released }
  SetLength(b, 0);
  Check(Length(b) = 0);
end.
