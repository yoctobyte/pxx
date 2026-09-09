{$mode objfpc}
program test_field_access_on_an_operator_result;
{ `(x + y).v` -- a field read directly off an overloaded operator's RESULT.

  It answered `IR_UNSUPPORTED: frontend could not lower AST node (kind 5)`
  while `z := x + y; z.v` was correct, and the two are the same expression. The
  message named an internal node kind, so a reader hit it, added the temporary
  and never learned there was a rule.

  ROW 3 IS AN INDEX, NOT A SECOND FIELD, and it is here because it was one of
  the ticket's two open questions -- `(p - q).a[0]` failed identically, since an
  index over an operator result reaches the same field/base walk. The other
  question was whether every aggregate-returning operator has it: a
  CLASS-returning operator was always fine, because the result is a pointer and
  no address is needed, so this is records only. Both measured rather than
  assumed; neither had been probed when the ticket was filed.

  THE FIX IS A NAME, NOT A MECHANISM. The parser leaves an overloaded operator
  as an AN_BINOP and only retypes it to the operator's result type; IRLowerAST
  turns that into a call, and a record-returning CALL used as a field base was
  already handled -- its IR value is the address of the hidden aggregate-result
  temp. The address walk simply did not list AN_BINOP beside AN_CALL.

  Rows 1-2 are the pair that matters: the temporary spelling and the direct one
  must agree. A row asserting only the direct one would pass on a build where
  both were wrong in the same way.

  The negative control is in the Makefile, not here: a record `+` with NO
  operator declared must still be refused by name rather than silently handed
  an address, which is the one way this arm could go wrong.

  ORACLE: fpc 3.2.2 prints this exactly, measured.
  bug-p-a-field-access-on-an-operator-result-does-not-lower }
type
  TFoo = record v: LongInt; end;
  TArr = record a: array[0..3] of LongInt; end;

operator + (a, b: TFoo) rr: TFoo;
begin rr.v := a.v + b.v; end;

operator - (a, b: TArr) rr: TArr;
begin rr.a[0] := a.a[0] - b.a[0]; end;

var
  x, y, z: TFoo;
  p, q: TArr;
begin
  x.v := 4;      y.v := 5;
  p.a[0] := 10;  q.a[0] := 3;

  z := x + y;
  WriteLn('via temp: ', z.v);
  WriteLn('direct:   ', (x + y).v);
  WriteLn('index:    ', (p - q).a[0]);
end.
