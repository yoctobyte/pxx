program test_qualified_units;

uses qualified_a, qualified_b;

{ Unit-qualified constant in a const expression (bug-unit-qualified-constant-
  not-resolved): `Unit.Const` must resolve in ConstEval, not just in ordinary
  expressions. }
const QC = qualified_a.SharedConst;

{ A program variable spelled exactly like a unit's untyped string const. Both
  readings have to hold: the BARE name is the program's variable (Pascal scoping,
  and the reason the guard being tested exists at all), the QUALIFIED name is the
  unit's const. Verified against FPC 3.2.2, which prints these two lines.
  bug-n-assigning-to-a-name-that-collides-with-a-pascal-shim-attribute-fails }
var SharedTag: AnsiString;

begin
  SharedTag := 'from-program';
  writeln(SharedTag);
  writeln(qualified_a.SharedTag);
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
