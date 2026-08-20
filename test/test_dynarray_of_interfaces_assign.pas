{ `b := a` on a dynamic array of INTERFACES was lowered as an ARC interface
  assignment over the array HANDLE.

  An array's TypeKind IS its element kind, so the assignment path arrived with
  lhsTk = tyRecord and ResolveNodeRec answering IFoo, decided the destination was
  a COM interface value, and emitted

    PXXIntfAssign(@b, @a, ifaceId)

  which reads a dynamic-array handle as an interface fat pointer and dispatches
  _Release through whatever that word points at. SIGSEGV -- and it did not depend
  on the elements at all: an array whose every element was still nil crashed just
  the same, because nothing about the elements is involved.

  `array of Integer`, `array of string` and `array of <plain record>` were all
  fine; only the interface element type routed into the ARC path. The fix asks
  about the CONTAINER rather than the member -- an array assignment is a
  whole-array copy whatever its elements are.

  Every expectation is `fpc -O- -Mobjfpc` 3.2.2's.
  bug-a-assigning-a-dynamic-array-of-interfaces-is-lowered-as-an-interface-assign }
program test_dynarray_of_interfaces_assign;
{$mode objfpc}{$H+}

type
  IFoo = interface
    ['{11111111-1111-1111-1111-111111111111}']
    function Name: string;
  end;
  TFoo = class(TInterfacedObject, IFoo)
    fN: string;
    constructor Create(const n: string);
    destructor Destroy; override;
    function Name: string;
  end;
  TArr2 = array[0..1] of IFoo;
  THold = record arr: TArr2; end;

var
  destroyed, pass, fail: Integer;

constructor TFoo.Create(const n: string); begin inherited Create; fN := n; end;
destructor TFoo.Destroy; begin Inc(destroyed); inherited Destroy; end;
function TFoo.Name: string; begin Result := fN; end;

procedure Chk(const what: string; ok: Boolean);
begin
  if ok then begin Inc(pass); writeln('ok   ', what); end
  else begin Inc(fail); writeln('FAIL ', what); end;
end;

{ 1. the crash: assigning one dyn array of interfaces to another }
function DynAssign: Boolean;
var a, b: array of IFoo;
begin
  SetLength(a, 1);
  a[0] := TFoo.Create('z');
  b := a;
  Result := b[0].Name = 'z';
  a[0] := nil;
end;

{ 2. the same with every element still NIL -- this crashed too, which is what
     showed the elements were never the point }
function DynAssignEmpty: Boolean;
var a, b: array of IFoo;
begin
  SetLength(a, 3);
  b := a;
  Result := (Length(b) = 3) and (b[0] = nil) and (b[2] = nil);
end;

{ 3. FPC dyn-array assignment ALIASES: both names share one handle, so nilling
     an element through one is visible through the other }
function DynAssignAliases: Boolean;
var a, b: array of IFoo;
begin
  SetLength(a, 1);
  a[0] := TFoo.Create('y');
  b := a;
  destroyed := 0;
  a[0] := nil;
  Result := (b[0] = nil) and (destroyed = 1);
end;

{ 4. a STATIC array of interfaces copies by VALUE, not by handle }
function StaticArrayCopy: Boolean;
var a, b: TArr2;
begin
  a[0] := TFoo.Create('s');
  b := a;
  Result := b[0].Name = 's';
  a[0] := nil; b[0] := nil;
end;

{ 5. a record holding an interface array, and the array field on its own }
function RecordWithArray: Boolean;
var h, g: THold;
begin
  h.arr[0] := TFoo.Create('r');
  g := h;
  Result := g.arr[0].Name = 'r';
  g.arr := h.arr;
  Result := Result and (g.arr[0].Name = 'r');
  h.arr[0] := nil; g.arr[0] := nil;
end;

{ 6. element types that always worked -- kept so a fix cannot break them }
function OtherElementTypes: Boolean;
var ai, bi: array of Integer; asr, bs: array of string;
begin
  SetLength(ai, 1); ai[0] := 7; bi := ai;
  SetLength(asr, 1); asr[0] := 'q'; bs := asr;
  Result := (bi[0] = 7) and (bs[0] = 'q');
end;

begin
  pass := 0; fail := 0;

  Chk('dyn array of interfaces: b := a', DynAssign);
  Chk('dyn array assign with all elements nil', DynAssignEmpty);
  Chk('dyn array assign aliases the handle', DynAssignAliases);
  Chk('static array of interfaces copies by value', StaticArrayCopy);
  Chk('record holding an interface array', RecordWithArray);
  Chk('integer and string element types still work', OtherElementTypes);

  writeln;
  writeln('total ok ', pass, ' / ', pass + fail);
end.
