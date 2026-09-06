unit ualias;
{ Re-declares the two names builtinheap already owns, exactly as
  lib/rtl/classes.pas does and for the same stated reason: FPC hands every unit
  IInterface/IUnknown from System and pxx has no System. The point of the
  fixture is that a CONSUMER of this unit must see THESE rows, not the ones
  builtinheap registered first. }
{$mode objfpc}
interface
type
  IInterface = interface ['{00000000-0000-0000-C000-000000000046}']
  end;
  IUnknown = IInterface;
implementation
end.
