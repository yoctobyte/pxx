{ MUST NOT COMPILE, and it is the row the call site warned about in advance: a
  method resolution clause rewrites the name and reaches the SAME lookup, so
  this must refuse exactly as the plain spelling does. A check written inside
  the clause branch would make the clause stricter than the spelling it
  desugars to. The diagnostic names the INTERFACE method and then the class
  method, so the reader is told which obligation was missed rather than only
  which method they wrote.
  bug-p-the-imt-signature-fallback-hands-off-a-refusal-nobody-makes }
program test_an_interface_clause_arity_mismatch_is_refused_fail;
{$mode objfpc}
type
  IFoo = interface function M(a: LongInt): LongInt; end;
  TFoo = class(TInterfacedObject, IFoo)
    function MyM: LongInt;
    function IFoo.M = MyM;
  end;
function TFoo.MyM: LongInt; begin Result := 7; end;
var f: IFoo;
begin
  f := TFoo.Create;
  WriteLn(f.M(1));
end.
