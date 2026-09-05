{ The SIBLING of test_char_array_3d_row_not_a_string_fail, on the base that arm
  did not accept when that file was written.

  ASTCharArrayCap's AN_INDEX arm refused a DEREF base for a day, so the 3-D
  guard there was only ever exercised through a plain variable. Admitting the
  deref makes `q^[0]` on a 3-D pointee reach the same predicate, and the
  `ASTNDRowSubs = NDInfoNDims - 1` test is the only thing that stops it: two
  subscripts remain, so `q^[0]` names a 2-D sub-array and fpc refuses a string
  there ("got Constant String expected Array[0..1] Of Array[0..3] Of Char").

  Widening a predicate to a new base widens every guard inside it to that base
  too, and a guard nothing exercises on the new base is not a guard.
  devdocs/dev/normalise-dont-special-case.md, "grep for the sibling". }
program test_char_array_3d_row_through_a_deref_not_a_string_fail;
type
  T3D = array[0..1, 0..1, 0..3] of Char;
  P3D = ^T3D;
var
  q : P3D;
begin
  New(q);
  q^[0] := 'hi';
  writeln(q^[0][0][0]);
end.
