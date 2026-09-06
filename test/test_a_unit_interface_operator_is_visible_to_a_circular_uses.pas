{ An operator declared in a unit's INTERFACE must be registered there, not only
  when its implementation body is parsed. Under a circular implementation-`uses`
  the body has not been parsed yet when the other unit is compiled, and the
  symptom was `no operator overload found for record operands` on a program fpc
  3.2.2 accepts (fpc testsuite toperator1/2/3).

  The last two rows are the positive control for the NAME SCHEME the fix needed:
  a unary and a binary `-` on the same record differ only in parameter count, so
  they collide unless arity is part of the synthesised proc name -- and a
  collision is silent, it just runs the wrong body. }
program test_a_unit_interface_operator_is_visible_to_a_circular_uses;

uses uopcirca, uopcircb;

var
  a, b, c: TCA;
  d, e, f: TCB;
begin
  UseBsOperator;
  UseAsOperator;
  a.x := 67; a.y := -45;
  b.x := 89; b.y := 23;
  c := a + b;
  WriteLn('program, A operator: ', c.x, ' ', c.y);
  d.x := 1; d.y := 2;
  e.x := 30; e.y := 40;
  f := d + e;
  WriteLn('program, B operator: ', f.x, ' ', f.y);
  c := a - b;
  WriteLn('binary minus       : ', c.x, ' ', c.y);
  c := -a;
  WriteLn('unary  minus       : ', c.x, ' ', c.y);
end.
