program test_a_for_in_enumerator_needs_a_parameterless_movenext_operator;
{$mode objfpc}{$H+}
{ MUST NOT COMPILE: an `operator enumerator` whose result type has a parametered MoveNext.

  A MoveNext that takes arguments is not the protocol's MoveNext, and the
  lowering calls it with none -- the parameter slot was never written and the
  loop ran on whatever was in it. fpc 3.2.2 refuses both arms:
  `Cannot find a "MoveNext" method in enumerator "TBad"`.

  TWO FILES BECAUSE THERE ARE TWO ARMS AND ONLY ONE RESOLVER. The rule lives in
  EnumeratorMoveNextMeth, which both the operator arm and the GetEnumerator arm
  go through; a fix placed at either CALL site would leave the other accepting.
  These two rows are what says it is in the resolver.

  The sibling positive controls are the seven test_for_in_* fixtures and
  tforin9.pp, whose IMyIterator nominates its MoveNext through the
  `enumerator MoveNext` directive on an INTERFACE -- the shape that decides the
  arity test is `> 1` (Self counted) rather than `<> 1`.
  tforin22.pp }
type
  TBad = class
    F: Integer;
    function MoveNext(a: Integer): Boolean;
    property Current: Integer read F;
  end;
function TBad.MoveNext(a: Integer): Boolean; begin Result := False; end;

operator enumerator(a: Integer): TBad;
begin Result := TBad.Create; Result.F := a; end;

var i, v: Integer;
begin
  v := 1;
  for i in v do WriteLn(i);
end.
