program test_qualified_units;

uses qualified_a, qualified_b;

begin
  qualified_a.SetShared(3);
  qualified_b.SetShared(7);
  writeln(qualified_a.SharedValue);
  writeln(qualified_b.SharedValue);
  writeln(qualified_a.SharedFunc);
  writeln(qualified_b.SharedFunc);
  writeln(qualified_a.SharedAdd(1));
  writeln(qualified_b.SharedAdd(1));
end.
