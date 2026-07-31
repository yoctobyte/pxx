{ bug-pascal-defines-leak-across-units: same repro as order1.pas with the
  `uses` clause reversed. Before the fix, this order printed "ub does not
  see it" while order1 printed "ub SEES ua's define" — same two units,
  different object code, purely from `uses` order. Both must agree now. }
program test_pascal_define_unit_scope_order2;
uses ub, ua;
begin
  B;
  A;
end.
