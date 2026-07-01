program TestConstArrayOfString;
{ Regression for bug-const-array-of-ansistring-literal-too-many-elements:
  a `const arr: array[..] of AnsiString = (...)` initializer with multi-char
  string elements desynced the element-counting loop from the token stream
  (ConstEvalFactor has no branch for a >1-char string literal and silently
  fails to advance), firing a spurious "too many array constant elements"
  error; single-char elements compiled but stored Ord(char) where a managed-
  string handle was expected, segfaulting at runtime. }
const
  Multi: array[0..3] of AnsiString = ('aa', 'bb', 'cc', 'dd');
  OneChar: array[0..3] of AnsiString = ('a', 'b', 'c', 'd');

procedure LocalConstTest;
const
  L: array[0..2] of AnsiString = ('xx', 'yy', 'zz');
var j: Integer;
begin
  for j := 0 to 2 do
    write(L[j], ' ');
  writeln;
end;

var
  i: Integer;
  s: AnsiString;
begin
  for i := 0 to 3 do write(Multi[i], ' ');
  writeln;
  for i := 0 to 3 do write(OneChar[i], ' ');
  writeln;
  LocalConstTest;
  { reassigning after init proves the element is a real managed-string
    handle (ARC release+realloc), not a raw literal alias }
  s := Multi[1];
  Multi[1] := 'zzz';
  writeln(Multi[1], ' ', s);
end.
