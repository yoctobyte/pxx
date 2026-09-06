program test_generic_body_sees_its_specializations_nested_type;
{$mode objfpc}
{ A template's method body parses as its DECLARING unit (so a private helper
  beside it wins over a same-named one in the program). That is correct and it
  is not the whole scope: a specialization's SYNTHESIZED rows -- the class minted
  for a nested `TEnumSpec = specialize TEnum<T>` -- are minted where the
  specialization is WRITTEN, which here is this program. Becoming the declaring
  unit made those invisible, because a unit genuinely cannot see the program's
  classes, and TList's own `TEnumSpec.Create` came out as
  `undefined variable (TEnumSpec)` against a class row that existed.

  Measured on real FPC `fgl.pp` first (`TFPGListEnumeratorSpec`, unit=-1 against
  CurrentUnitIdx=62) -- but that arm SKIPS on a checkout without the FPC RTL
  source, so the regression is guarded here, where it needs no corpus.

  Two classes declare a nested type of the SAME NAME on purpose: the fix must
  restore a name that exists only in the host scope WITHOUT letting one class's
  nested type answer for another's. }
uses unestspec;
type
  TThing = class(TObject) N: Integer; end;
  IFoo = interface ['{11111111-2222-3333-4444-555555555555}']
    function Val: Integer;
  end;
  TFoo = class(TInterfacedObject, IFoo)
    function Val: Integer;
  end;
  TLI = specialize TList<Integer>;
  TOI = specialize TOther<Integer>;
  TCL = specialize TCastList<TThing>;
  TIL = specialize TIfList<IFoo>;
function TFoo.Val: Integer; begin Result := 66; end;
var
  l: TLI; o: TOI; c: TCL; t: TThing; il: TIL; f: IFoo;
begin
  l := TLI.Create; l.Item := 33;
  o := TOI.Create; o.Item := 44;
  WriteLn(l.GetEnumerator.V, ' ', o.GetEnumerator.V);
  { the type ARGUMENT, declared in this program and named inside the template's
    body by a cast -- fgl's `T(FList.Items[FPosition]^)` }
  t := TThing.Create; t.N := 55;
  c := TCL.Create; c.Slot := Pointer(t);
  WriteLn(c.GetCurrent.N);
  { the interface arm -- fgl's ifclist row }
  f := TFoo.Create;
  il := TIL.Create; il.Slot := Pointer(f);
  WriteLn(il.GetCurrent.Val);
end.
