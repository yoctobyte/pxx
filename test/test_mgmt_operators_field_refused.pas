program test_mgmt_operators_field_refused;
{ THIS FIXTURE EXPIRED AND WAS RE-AIMED, which is the whole hazard of a test
  that asserts a NEGATIVE. It used to hold a plain `f: TFoo` field, and that
  shape now COMPILES -- the desugar walks the field table and builds a field
  path. A fixture asserting "this is refused" turns red the day someone
  implements it, and the correct repair is to point it at what is still refused
  rather than to delete it.

  What is still refused, and why it is not the same shape: an ARRAY field needs
  the synthesised loop the array-of-record SYMBOL needs, which is the other arm
  of the ticket. UFldTk carries the ELEMENT kind for an array field, so
  `tyRecord` alone cannot separate the two and UFldIsArray is what does -- a
  guard that reads only the kind lets this through silently.
  feature-pascal-management-operators-nested-and-array }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;
    class operator Initialize(var a: TFoo);
  end;
  TBar = record
    f: array[0..1] of TFoo;
    k: Integer;
  end;
class operator TFoo.Initialize(var a: TFoo);
begin a.n := 0; end;

procedure P;
var b: TBar;
begin
  b.k := 1;
end;

begin
  P;
end.
