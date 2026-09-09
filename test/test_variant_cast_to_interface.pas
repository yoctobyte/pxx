{ `IFoo(v)` on a Variant CONVERTS, and used to segfault.

  The cast site builds AN_CLASS_CAST typed tyClass, which is right for
  `IFoo(p)` -- a hard reinterpret of a pointer-shaped container, how FPC spells
  recovering an interface, and only expressible because an interface value is
  one machine word. A Variant is not pointer-shaped: the reinterpret handed the
  16-byte record's TAG WORD to the ARC path as an instance pointer. `g := v`
  had been correct since bug-p-a-variant-cannot-hold-an-interface, so the two
  spellings of one operation disagreed and only one of them crashed.

  BYTE-IDENTICAL TO fpc 3.2.2 ON ALL SIX ROWS, verified 2026-09-09 -- including
  the destructor count, which is what makes rows 3-6 a lifetime assertion and
  not just a value one. Both compilers hold the object to scope exit here,
  because row 2's expression-position cast materialises a temp of its own.

  THAT MASKING IS WORTH KNOWING, because the pure-assignment shape does NOT
  agree: with row 2 removed, fpc destroys at `g := nil` and pxx at scope exit.
  pxx's conversion materialises an OWNING temp and releases it at scope exit,
  the same model `obj as IFoo` already uses (IRMaterializeIntfCast retains its
  temp; scope exit releases it), so matching fpc for one of the two casts would
  give them different lifetime rules. The object's lifetime is longer, never
  shorter -- no row can observe a freed object -- and the divergence is recorded
  with its own repro in the ticket. Do not "fix" this file by asserting the
  shorter lifetime; measure the two-line program the ticket carries.

  Row 5 is the EMPTY half of the read-back's refusal: an unset variant yields
  nil in both compilers. The refusing half -- a variant holding a NUMBER -- is
  not a row here because it cannot be one: pxx halts 220 (FPC's own
  invalid-variant-typecast code) and fpc raises EVariantTypeCastError. Row 5
  asserts which half does NOT refuse.
  bug-p-a-variant-typecast-to-an-interface-segfaults }
{$mode objfpc}{$H+}
program test_variant_cast_to_interface;
type
  IFoo = interface ['{A0000000-0000-0000-0000-000000000001}']
    function Twice(n: Integer): Integer;
  end;
  TImpl = class(TInterfacedObject, IFoo)
    function Twice(n: Integer): Integer;
    destructor Destroy; override;
  end;

var
  Destroyed: Integer;

function TImpl.Twice(n: Integer): Integer; begin Result := n + n; end;
destructor TImpl.Destroy; begin Inc(Destroyed); inherited Destroy; end;

procedure Run;
var
  v, u: Variant;   { u is never assigned: an EMPTY slot }
  f, g, h: IFoo;
begin
  f := TImpl.Create;
  v := f;
  f := nil;
  g := IFoo(v);
  WriteLn('1 cast              twice(21)=', g.Twice(21), ' destroyed=', Destroyed);
  WriteLn('2 in an expression  twice(4)=', IFoo(v).Twice(4), ' destroyed=', Destroyed);
  v := 0;
  WriteLn('3 variant cleared   destroyed=', Destroyed);
  g := nil;
  WriteLn('4 g dropped         destroyed=', Destroyed);
  h := IFoo(u);
  WriteLn('5 empty slot        h=nil? ', h = nil, ' destroyed=', Destroyed);
end;

begin
  Destroyed := 0;
  Run;
  WriteLn('6 after scope exit  destroyed=', Destroyed);
end.
