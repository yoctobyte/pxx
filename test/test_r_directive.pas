program test_r_directive;
{$R-}
{ Range-check toggle must be a no-op, not a resource directive.
  See bug-r-directive-toggle-treated-as-resource. }
var i: Integer;
begin
  i := 41;
  {$R+}
  i := i + 1;
  writeln(i);
end.
