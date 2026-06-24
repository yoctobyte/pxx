{ Regression: Length() of a dynamic-array function-call result.
  bug-length-of-dynarray-call-result — the inline call result was derefed as an
  address ([rax]) and read element 0 (gave 0), or segfaulted for managed
  elements. Length(F()) must equal Length(v) where v := F(). }
program test_length_dynarray_call;
type
  TA = array of Integer;
  TS = array of AnsiString;
function MakeArr(n: Integer): TA;
var i: Integer;
begin
  SetLength(Result, n);
  for i := 0 to n - 1 do Result[i] := i;
end;
function MakeEmpty: TA;
begin
  SetLength(Result, 0);
end;
function MakeStrs(n: Integer): TS;
var i: Integer;
begin
  SetLength(Result, n);
  for i := 0 to n - 1 do Result[i] := 'x';
end;
var a: TA;
begin
  a := MakeArr(3);
  writeln(Length(a));               { 3 — via var (control) }
  writeln(Length(MakeArr(3)));      { 3 — inline (was 0) }
  writeln(Length(MakeArr(0)));      { 0 — inline empty }
  writeln(Length(MakeEmpty));       { 0 — inline empty, no-arg }
  writeln(Length(MakeStrs(4)));     { 4 — managed elem inline }
  writeln(Length(MakeStrs(0)));     { 0 — managed elem inline empty (was segfault) }
end.
