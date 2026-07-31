{ bug-pascal-defines-leak-across-units: `{$define}` in `ua` (test/units_defscope)
  must stay invisible to `ub`, which never uses `ua` — regardless of which
  order this program names them. Paired with order2.pas, which swaps the
  order; both must print the same thing. }
program test_pascal_define_unit_scope_order1;
uses ua, ub;
begin
  A;
  B;
end.
