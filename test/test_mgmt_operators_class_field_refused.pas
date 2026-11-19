program test_mgmt_operators_class_field_refused;
{ A class field whose record holds a management-operator record only one level
  DEEPER is still refused. A field of the operator-declaring record itself (or
  a fixed array of it) is run at Create/Free from the class layout descriptor
  (test_mgmt_operators_class_field.pas); the nested shape needs the record's
  own field walk at object lifetime, which is not built, and compiling it
  would silently never run the inner Initialize.

  Re-aimed 2026-11-20 when the direct shape landed: this fixture used to refuse
  the direct shape. feature-pascal-management-operators-on-a-class-field }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;
    class operator Initialize(var a: TFoo);
  end;
  TWrap = record
    inner: TFoo;
  end;
  TCls = class
  public
    w: TWrap;
  end;
class operator TFoo.Initialize(var a: TFoo);
begin a.n := 0; end;

procedure P;
var c: TCls;
begin
  c := nil;
  if c <> nil then WriteLn('no');
end;

begin
  P;
end.
