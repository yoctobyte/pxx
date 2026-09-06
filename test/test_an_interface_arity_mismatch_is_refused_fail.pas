{ MUST NOT COMPILE. The plain spelling: a class claims IFoo and implements `M`
  with no parameter where the interface declares one. Compiled clean before the
  fix and `f.M(1)` called the 0-argument body.
  bug-p-the-imt-signature-fallback-hands-off-a-refusal-nobody-makes }
program test_an_interface_arity_mismatch_is_refused_fail;
{$mode objfpc}
type
  IFoo = interface function M(a: LongInt): LongInt; end;
  TFoo = class(TInterfacedObject, IFoo) function M: LongInt; end;
function TFoo.M: LongInt; begin Result := 7; end;
var f: IFoo;
begin
  f := TFoo.Create;
  WriteLn(f.M(1));
end.
