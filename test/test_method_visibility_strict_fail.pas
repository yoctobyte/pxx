program test_method_visibility_strict_fail;
{$mode objfpc}
{ Under --strict-visibility a STRICT PRIVATE method must be rejected even from
  a descendant (type-scoped, tclass12b shape on a method). Compiled by make
  test with the flag ON and expected to FAIL with "cannot access strict
  private". Compiles fine under the lax default. }
type
  TA = class
  strict private
    procedure Secret;
  public
    procedure Go;
  end;
  TB = class(TA)
  public
    procedure Leak;
  end;

procedure TA.Secret; begin end;
procedure TA.Go; begin Secret; end;      { own class -> ok }
procedure TB.Leak; begin Secret; end;    { descendant -> must be rejected }

var b: TB;
begin
  b := TB.Create;
  b.Leak;
end.
