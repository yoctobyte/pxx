{ NEGATIVE CONTROL, and it is the load-bearing one for the AN_INDEX arm of
  ASTCharArrayCap.

  `a[0]` on a 3-D Char array names a 2-D SUB-ARRAY, not a row, and fpc refuses
  a string there ("got Constant String expected Array[0..1] Of Array[0..3] Of
  Char"). NDRowSourceInfo will happily return the PRODUCT of the trailing
  dimensions for it -- 8 here -- which is a plausible number and the wrong one:
  a capacity that spans rows is a buffer write past the row.

  Drop the `ASTNDRowSubs = NDInfoNDims - 1` test and every positive row in
  test_char_array_nd_row_is_a_string still passes, because they are all 2-D and
  one subscript IS all-but-one there. This file is the only thing that fails. }
program test_char_array_3d_row_not_a_string_fail;
var
  a : array[0..1, 0..1, 0..3] of Char;
begin
  a[0] := 'hi';
  writeln(a[0][0][0]);
end.
