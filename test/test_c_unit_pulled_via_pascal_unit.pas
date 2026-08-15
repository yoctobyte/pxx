program test_c_unit_pulled_via_pascal_unit;
{ The program names only the Pascal unit. The C file behind it, its malloc
  bridge, and the fact that the unit's own body can see what the C file
  declares are all the unit's business — which is the point: this is the
  legitimate direct edge, not a transitive one. }
uses unit_c_bridge;
begin
  writeln(Twice(21));
end.
