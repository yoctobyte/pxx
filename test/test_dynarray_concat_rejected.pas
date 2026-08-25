program test_dynarray_concat_rejected;
{ A MEANINGLESS arithmetic operator on a dynamic array must be rejected at
  compile time with a clear error, NOT silently miscompiled into a pointer-add
  that segfaults at runtime (bug-dynarray-concat-silent-miscompile).

  `a + b` over TWO dynamic arrays used to be in this set and is now defined as
  concatenation (feature-p-dynamic-array-concatenation, covered positively by
  test_dynamic_array_concatenation.pas). What must still be LOUD is the rest:
  `-`, `*`, `div`, and -- tested here, because it is the boundary the new
  feature moved -- a `+` with an array on only ONE side. They all land on the
  same arm in ir.inc; this is the arm's tightest condition. }
var a, c: array of Integer;
    n: Integer;
begin
  SetLength(a, 2); a[0] := 1; a[1] := 2;
  n := 1;
  c := a + n;
  writeln(Length(c));
end.
