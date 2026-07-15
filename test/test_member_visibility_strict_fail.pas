program test_member_visibility_strict_fail;
{$mode objfpc}
{ %FAIL under --strict-visibility: a strict private member is type-scoped, so a
  DESCENDANT class's method cannot reach it (the tclass12b conformance shape, on a
  field). Compiles under the lax default; rejected under --strict-visibility. }
type
  TBase = class
  strict private
    FSecret: integer;
  end;
  TDerived = class(TBase)
  public
    procedure Poke;
  end;

procedure TDerived.Poke;
begin
  FSecret := 9;     { strict private of the ANCESTOR, from a descendant -> illegal }
end;

var d: TDerived;
begin
  d := TDerived.Create;
  d.Poke;
end.
