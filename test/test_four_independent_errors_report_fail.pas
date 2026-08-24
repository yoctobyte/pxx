{ FOUR different kinds of name that does not resolve, in one file: an unknown
  TYPE, an unknown MEMBER, a call to a procedure that does not exist, and a
  function that does not exist inside an expression.

  fpc 3.2.2 reports all four (plus a follow-on "Error in type definition" for
  the first). This compiler reported the first and stopped, so a file with four
  typos cost four compile cycles.

  The `NoSuchProc(1, 2);` row is the one that needs statement RESYNC rather than
  a stand-in: a procedure call is not an assignment, so the recovered statement
  has nothing to be, and without the resync it died on `unexpected token` —
  which buries the real diagnostic and stops the file anyway.
  feature-a-error-does-not-halt-so-a-parse-can-be-speculative }
program test_four_independent_errors_report_fail;
type TR = record a: Integer; end;
var
  x: TUnknownType;
  r: TR;
  i: Integer;
begin
  i := r.nofield;
  NoSuchProc(1, 2);
  i := NoSuchFunc(3);
  writeln(i, x);
end.
