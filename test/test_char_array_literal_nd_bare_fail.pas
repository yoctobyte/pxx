{ NEGATIVE CONTROL, and it is the one that keeps the shorthand NARROW.

  The literal shorthand is ONE-DIMENSIONAL: fpc 3.2.2 refuses a bare literal for
  a multi-dimensional char array (`Syntax error, "(" expected but "const string"
  found`) and so do we. Rows inside a parenthesised list are the N-D spelling and
  they are exercised as positives elsewhere.

  Without this row, widening the arm from `cnNDims = 1` to "any char array"
  passes every positive test in the group -- 'abcdef' would fill a 2x3 array
  row-major and print the same characters -- while silently accepting a
  declaration the language does not have. The observable it protects is the
  DIAGNOSTIC, which is the only thing that differs. }
program test_char_array_literal_nd_bare_fail;
const
  c : array[1..2, 1..3] of Char = 'abcdef';
begin
  writeln(c[1][1]);
end.
