{ %FAIL negative: field access THROUGH an interface-typed variable.
  An interface exposes ONLY its declared methods, never the implementing class's
  fields; FPC rejects `iw0.fi` with "identifier idents no member". pxx used to
  resolve it as a class-field offset through the interface pointer and miscompile
  to a SIGSEGV (bug-pascal-field-access-through-interface-var). The interface
  method call `iw0.Ic0(0)` stays valid. }
program test_interface_field_access_fail;
type
  IPas0 = interface ['{11111111-0000-0000-0000-000000000001}'] function Ic0(a: longint): longint; end;
  TIfc = class(TInterfacedObject, IPas0) fi: longint; function Ic0(a: longint): longint; end;
var iw0: IPas0;
function TIfc.Ic0(a: longint): longint; begin Ic0 := a + fi; end;
begin
  iw0 := TIfc.Create;
  iw0.fi := 100;          { field access THROUGH an interface var — rejected }
  writeln(iw0.Ic0(0));
  iw0 := nil;
end.
