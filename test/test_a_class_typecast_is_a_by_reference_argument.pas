{ FPC's "variable typecast" — a hard cast over an lvalue — is itself an lvalue,
  so it may be passed to a `var` parameter and the callee's writes reach the
  caller's variable. pxx accepted the POINTER spelling and refused the CLASS one:

    error: by-reference argument must be a variable

  `IsVarArgLvalueCast` listed `AN_PTR_CAST` and nothing else, because that is the
  spelling that had a caller when the list was written. `IRLowerAddress` has
  peeled BOTH kinds since the interface-cast arm went in, so the capability was
  already there and only the door was short a member.

  fcl-passrc's pastree.pp:2101 is the live case and it is the whole point of the
  idiom: `ReleaseAndNil(TPasElement(InterfaceName))` must nil the caller's field,
  three times in one destructor.

  THE `as` ROW IS THE CONTROL AND IT MUST STAY REFUSED. `d as TBase` performs a
  checked conversion and yields a VALUE; fpc refuses it in this position too
  (`Can't take the address of constant expressions`, fpc 3.2.2). A hard cast
  reinterprets an lvalue, a checked cast produces one, and a fix that accepted
  both would take a temp's address and drop the callee's write on the floor —
  silently, since the call still compiles and the object is still touched. It
  cannot be a row in this file because it must not compile; it is asserted by
  the twin refusal test instead, and named here so the next reader does not
  "complete" the list.

  Both spellings of the cast are in this one file, and both assert that the
  callee's NIL reached the caller — not that the call compiled. A cast that
  materialised a temp would let every call through and change no output but the
  one this file prints.
  bug-p-a-class-typecast-is-refused-as-a-by-reference-argument }
{$mode objfpc}
program test_a_class_typecast_is_a_by_reference_argument;
type
  TBase = class
    N: Integer;
  end;
  TDer = class(TBase)
    M: Integer;
  end;
  TOwner = class
    Fld: TDer;
    Arr: array of TDer;
  end;
  PDer = ^TDer;

procedure Bump(var e: TBase);
begin
  if e <> nil then
  begin
    e.N := e.N + 7;
    e := nil;              { the write the caller must see }
  end;
end;

procedure BumpPtr(var p: PtrUInt);
begin
  p := p + 1;
end;

function Live(d: TDer): AnsiString;
begin
  if d = nil then Live := 'nil' else Live := 'live';
end;

var
  d: TDer;
  o: TOwner;
  u: PtrUInt;
begin
  { a plain variable }
  d := TDer.Create; d.N := 1;
  Bump(TBase(d));
  WriteLn('var    : ', Live(d));

  { a FIELD }
  o := TOwner.Create;
  o.Fld := TDer.Create; o.Fld.N := 2;
  Bump(TBase(o.Fld));
  WriteLn('field  : ', Live(o.Fld));

  { an array ELEMENT. Arr[0] is CREATED so the neighbour row can discriminate:
    an un-created slot is nil too, and `nil` is exactly what a correct Bump
    writes -- the expected value would collide with the failure value and the
    control could not fail. }
  SetLength(o.Arr, 2);
  o.Arr[0] := TDer.Create; o.Arr[0].N := 9;
  o.Arr[1] := TDer.Create; o.Arr[1].N := 3;
  Bump(TBase(o.Arr[1]));
  WriteLn('element: ', Live(o.Arr[1]), ' neighbour: ', Live(o.Arr[0]), ' ', o.Arr[0].N);

  { the pointer spelling, which already worked — the control for no regression }
  u := 41;
  BumpPtr(PtrUInt(u));
  WriteLn('ptrcast: ', u);
end.
