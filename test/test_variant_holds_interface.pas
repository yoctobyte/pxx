{ A Variant can hold an interface, and holding one is a REFERENCE.

  Both assertion directions, because this defect class cannot fail a value
  check from one side alone: a missing retain shows up only as an object that
  died too early, and a missing release only as one that never dies at all.
  So every row prints the destructor count, and the rows are arranged so that
  the object's death has exactly one legal moment.

  Row 6 is the read-back's two-sided control on an EMPTY slot: it must yield
  nil (not eight reinterpreted bytes) AND still release what the destination
  held (not leak it) -- h is holding the object when the row runs, and row 7
  proves the count reached zero only after the LAST holder let go.

  A slot holding a number or a string is NOT here: it halts with 220, FPC's
  invalid-variant-typecast code, which is deliberate and measured against fpc
  3.2.2 -- see PXXIntfFromVariant in builtinheap.pas.
  bug-p-a-variant-cannot-hold-an-interface }
{$mode objfpc}{$H+}
program test_variant_holds_interface;
type
  IFoo = interface ['{A0000000-0000-0000-0000-000000000001}']
    procedure F;
  end;
  TImpl = class(TInterfacedObject, IFoo)
    procedure F;
    destructor Destroy; override;
  end;

var
  Destroyed: Integer;

procedure TImpl.F; begin WriteLn('F called'); end;
destructor TImpl.Destroy; begin Inc(Destroyed); inherited Destroy; end;

var
  v, w, u: Variant;   { u is never assigned: an EMPTY slot }
  f, g, h: IFoo;
begin
  Destroyed := 0;
  f := TImpl.Create;
  v := f;
  WriteLn('1 boxed              destroyed=', Destroyed);
  f := nil;
  WriteLn('2 source cleared     destroyed=', Destroyed);
  w := v;
  v := 0;
  WriteLn('3 copied, v cleared  destroyed=', Destroyed);
  g := w;
  g.F;
  WriteLn('4 read back          destroyed=', Destroyed);
  w := 0;
  WriteLn('5 w cleared          destroyed=', Destroyed);
  h := g;
  h := u;
  WriteLn('6 empty slot         h=nil? ', h = nil, ' destroyed=', Destroyed);
  g := nil;
  WriteLn('7 last ref dropped   destroyed=', Destroyed);
  w := 0;
  g := nil;
  h := u;
  WriteLn('8 cleared again      destroyed=', Destroyed);
end.
