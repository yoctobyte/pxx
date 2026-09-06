program test_mgmt_operators_class_field_refused;
{ A CLASS whose field is a managed record is refused, and it is NOT the record
  case with a different kind on it -- it is a different LIFETIME and therefore a
  different insertion point.

  Measured against fpc 3.2.2: for `c: TCls` with a managed record field, fpc
  runs the field's Initialize inside `TCls.Create` and its Finalize inside
  `Free`. Nothing happens at scope entry or scope exit. So the scope-bound
  try/finally this pass emits would finalize a LIVE heap object every time the
  variable's scope ended, and would never run at all for an object that outlives
  it. Wrong in both directions, which is why this stays a refusal rather than
  being folded into the field walk beside it.

  The fpc testsuite row usually cited for "the nested-field arm", tmoperator4,
  is actually THIS shape -- its `TA`/`TB` are classes -- so the corpus demand
  sits here and not on the record case that now works.
  feature-pascal-management-operators-nested-and-array }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;
    class operator Initialize(var a: TFoo);
  end;
  TCls = class
  public
    f: TFoo;
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
