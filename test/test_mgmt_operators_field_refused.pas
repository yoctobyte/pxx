program test_mgmt_operators_field_refused;
{ THIS FIXTURE HAS NOW EXPIRED TWICE, which is the whole hazard of a test that
  asserts a NEGATIVE: it turns red the day someone implements the thing, and the
  correct repair is to re-aim it at what is still refused rather than delete it.

  Round one: it held a plain `f: TFoo` field, and that shape started compiling
  when the desugar learned to walk the field table.
  Round two (2026-09-07): it held `f: array[0..1] of TFoo`, and that shape now
  compiles too -- a FIXED ONE-DIMENSIONAL array field is iterated by a
  synthesised loop under the field's own path.

  What is still refused, and why it is not the same shape: a DYNAMIC array field
  has no extent this pass can read. Its length is a runtime value, so there is
  no `hi` for the synthesised loop and the desugar would have to call Length()
  and build the loop against it. That is the remaining arm of the ticket.

  UFldTk carries the ELEMENT kind for an array field, so `tyRecord` alone
  cannot separate any of these three from each other; UFldIsArray separates a
  plain field from an array one and FldIsLoopableManagedArray separates the
  array shapes the loop can iterate from the ones it cannot. A guard reading
  only the kind lets all of them through silently.
  feature-pascal-management-operators-nested-and-array }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;
    class operator Initialize(var a: TFoo);
  end;
  TBar = record
    f: array of TFoo;
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
