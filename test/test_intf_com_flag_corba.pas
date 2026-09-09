{ The CORBA half of test_intf_com_flag, in its own file because
  {$interfaces corba} is a whole-unit switch and the COM rows must not be
  compiled under it.

  A1/A2/A3 PRINT ON PURPOSE. Under {$interfaces corba} on a plain TObject
  descendant, IMT slots 0/1/2 are these three methods -- so a helper that took
  "any entry's IMT, slot 2" would call A3, with the right argument count and no
  diagnostic. PXXIntfComIMTOf must find NO refcounted entry and both Any
  helpers must do nothing.

  If any `!! Ax CALLED` line appears, the walk fired on a population it must
  refuse. That is why the methods are loud rather than empty: `0` alone cannot
  tell a refusal from a call that happened to return zero.
  bug-p-a-variant-cannot-hold-an-interface }
{$mode objfpc}{$H+}
{$interfaces corba}
program test_intf_com_flag_corba;
type
  ICorbaA = interface procedure A1; procedure A2; procedure A3; end;
  TPlain = class(TObject, ICorbaA)
    procedure A1;
    procedure A2;
    procedure A3;
  end;
procedure TPlain.A1; begin WriteLn('!! A1 CALLED'); end;
procedure TPlain.A2; begin WriteLn('!! A2 CALLED'); end;
procedure TPlain.A3; begin WriteLn('!! A3 CALLED'); end;
var p: TPlain;
begin
  p := TPlain.Create;
  WriteLn('corba imt is nil: ', PXXIntfComIMTOf(Pointer(p)) = nil);
  WriteLn('corba addref: ', PXXIntfAddRefAny(Pointer(p)));
  WriteLn('corba release: ', PXXIntfReleaseAny(Pointer(p)));
  { the interface itself still WORKS -- refusing to refcount it is not
    refusing to call it }
  ICorbaA(p).A1;
  WriteLn('done');
end.
