program test_unary_minus_on_a_record_needs_an_operator;
{ fpc 3.2.2: Operator is not overloaded: - "R". pxx compiled it into an
  integer negation of the record and segfaulted.
  bug-a-unary-minus-on-a-record-without-an-operator-compiles-and-segfaults }
type R = record x, y: Double; end;
var a, b: R;
begin
  a.x := 1; a.y := 2;
  b := -a;
  writeln(b.x:0:1, ' ', b.y:0:1);
end.
