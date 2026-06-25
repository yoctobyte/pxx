program test_qualified_units;

uses qualified_a, qualified_b;

{ Unit-qualified constant in a const expression (bug-unit-qualified-constant-
  not-resolved): `Unit.Const` must resolve in ConstEval, not just in ordinary
  expressions. }
const QC = qualified_a.SharedConst;

begin
  writeln(QC);                          { 1074030207 — const-expression context }
  writeln(qualified_a.SharedConst);     { 1074030207 — ordinary-expression context }
  qualified_a.SetShared(3);
  qualified_b.SetShared(7);
  writeln(qualified_a.SharedValue);
  writeln(qualified_b.SharedValue);
  writeln(qualified_a.SharedFunc);
  writeln(qualified_b.SharedFunc);
  writeln(qualified_a.SharedAdd(1));
  writeln(qualified_b.SharedAdd(1));
end.
