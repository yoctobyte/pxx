{ Guard for bug-tobject-destroy-not-virtual-override: the root-virtual special
  case is scoped to Destroy/Create ONLY. `override` of any other method with no
  virtual slot in the parent chain must STILL be a hard error (not silently
  accepted as a fresh virtual). Compiling this must fail with
  "no virtual method found in parent chain". }
program test_override_bogus_rejected;
type
  TFoo = class
    procedure Bogus; override;
  end;
procedure TFoo.Bogus;
begin
end;
begin
end.
