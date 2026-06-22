program test_unit_impl_fwd;

{ Drives unit_impl_fwd, whose implementation uses every routine/const before it
  is declared (no `forward`). Compute = AddUp(4) + Helper = 10 + 100 = 110. }

uses unit_impl_fwd;

begin
  WriteLn(Compute);
end.
