program test_dynarray_concat_rejected;
{ Dynamic-array `a + b` is not implemented; it must be rejected at compile time
  with a clear error, NOT silently miscompiled into a pointer-add that segfaults
  at runtime (bug-dynarray-concat-silent-miscompile). }
var a, b, c: array of Integer;
begin
  SetLength(a, 2); a[0] := 1; a[1] := 2;
  SetLength(b, 2); b[0] := 3; b[1] := 4;
  c := a + b;
  writeln(Length(c));
end.
