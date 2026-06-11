program test_cross_dynarray;
{ Dynamic arrays on cross targets, compiled with -dPXX_MANAGED_STRING. Exercises
  the portable PXXDynSetLen helper (SetLength: alloc / copy min(old,new) / zero /
  retain managed elements / publish / release old), indexing, Length, and grow/
  shrink, for both scalar and AnsiString element types. Output is identical on
  every target (oracle pattern). }

var
  a: array of Integer;
  s: array of AnsiString;
  i, sum: Integer;
begin
  SetLength(a, 3);
  a[0] := 10; a[1] := 20; a[2] := 30;
  writeln(a[0], ' ', a[1], ' ', a[2], ' len=', Length(a));   { 10 20 30 len=3 }

  SetLength(a, 5);              { grow, prefix preserved }
  a[3] := 40; a[4] := 50;
  sum := 0;
  for i := 0 to Length(a) - 1 do sum := sum + a[i];
  writeln('sum=', sum, ' len=', Length(a));                  { sum=150 len=5 }

  SetLength(a, 2);             { shrink }
  writeln(a[0], ' ', a[1], ' len=', Length(a));              { 10 20 len=2 }

  SetLength(s, 3);
  s[0] := 'foo';
  s[1] := 'bar' + 'baz';
  s[2] := s[0];                { retain }
  writeln(s[0], ' ', s[1], ' ', s[2], ' len=', Length(s));   { foo barbaz foo len=3 }

  SetLength(s, 0);             { release all }
  writeln('len=', Length(s));                                { len=0 }
end.
