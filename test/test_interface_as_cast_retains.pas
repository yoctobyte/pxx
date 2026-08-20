{ `f := b as IFoo` moved the interface pointer WITHOUT retaining it.

  The ARC assignment path routes an interface-to-interface assignment through
  PXXIntfAssign (retain source, release old dest, copy) only when the RHS node
  is one of an ENUMERATED list of lvalue kinds. AN_AS_CAST was not in the list,
  so an as-cast RHS fell through to the generic 16-byte record copy, which moves
  the pointer raw.

  Three holders -- b, the hidden as-cast temp, and f -- then shared TWO counted
  references, and the object died one release early:

    b := TBar.Create;
    f := b as IFoo;
    b := nil;
    f := nil;              { destroyed HERE.  FPC keeps it alive, because the
                             as-cast temp still holds a reference until scope
                             exit }

  and the scope-exit release of that temp then ran on a freed object. That is
  only a LATENT use-after-free until something reuses the block, which is why it
  looked like a harmless finalization-timing difference on its own and turned
  into a SEGFAULT the moment a later statement allocated over it -- the original
  probe crashed at program exit, with all of its output already printed.

  The ownership rule the list encodes: an lvalue is a BORROW and must be
  retained; a call result is already OWNED and must not be (which is why
  `f := MakeFoo` was always right, and is checked below so a fix cannot
  over-retain it instead). An as-cast is a borrow from its own temp.

  Every expectation is `fpc -O- -Mobjfpc` 3.2.2's.
  bug-a-an-as-cast-assigned-to-an-interface-variable-is-not-retained }
program test_interface_as_cast_retains;
{$mode objfpc}{$H+}
uses sysutils;

type
  IFoo = interface
    ['{11111111-1111-1111-1111-111111111111}']
    function Name: string;
  end;
  IBar = interface(IFoo)
    ['{22222222-2222-2222-2222-222222222222}']
    function Extra: string;
  end;
  TFoo = class(TInterfacedObject, IFoo)
    fN: string;
    constructor Create(const n: string);
    destructor Destroy; override;
    function Name: string;
  end;
  TBar = class(TFoo, IFoo, IBar)
    function Extra: string;
  end;

var
  destroyed, pass, fail: Integer;

constructor TFoo.Create(const n: string); begin inherited Create; fN := n; end;
destructor TFoo.Destroy; begin Inc(destroyed); inherited Destroy; end;
function TFoo.Name: string; begin Result := fN; end;
function TBar.Extra: string; begin Result := 'x' + fN; end;

function MakeFoo(const n: string): IFoo; begin Result := TFoo.Create(n); end;

procedure Chk(const what: string; got, want: Integer);
begin
  if got = want then begin Inc(pass); writeln('ok   ', what, ' = ', got); end
  else begin Inc(fail); writeln('FAIL ', what, ' = ', got, ' want ', want); end;
end;

{ the core case: inside the routine the as-cast temp still holds a reference,
  so the object must NOT be destroyed; it dies when the routine returns }
procedure AsCastHoldsARef(var insideCount: Integer);
var f: IFoo; b: IBar;
begin
  b := TBar.Create('a');
  f := b as IFoo;
  b := nil;
  f := nil;
  insideCount := destroyed;
end;

{ a call result is OWNED, not borrowed -- it must NOT gain an extra retain,
  or the object would never die }
procedure CallResultIsOwned(var insideCount: Integer);
var f: IFoo;
begin
  f := MakeFoo('b');
  f := nil;
  insideCount := destroyed;
end;

{ an ordinary interface lvalue was always retained -- kept as the canary that
  the enumerated list still covers what it used to }
procedure LValueIsBorrowed(var insideCount: Integer);
var f, g: IFoo;
begin
  f := TFoo.Create('c');
  g := f;
  f := nil;
  insideCount := destroyed;   { g still holds it }
  g := nil;
end;

{ the shape that actually crashed: an as-cast, then a LATER allocation that can
  reuse the block, then program flow continues. Before the fix this segfaulted
  after all output had been printed. }
procedure UseAfterFreeShape;
var f: IFoo; b: IBar; i: Integer; keep: array[0..7] of IFoo;
begin
  b := TBar.Create('d');
  f := b as IFoo;
  b := nil; f := nil;
  for i := 0 to 7 do keep[i] := TFoo.Create('r' + IntToStr(i));
  for i := 0 to 7 do keep[i] := nil;
end;

var inside: Integer;
begin
  pass := 0; fail := 0;

  destroyed := 0;
  AsCastHoldsARef(inside);
  Chk('as-cast: alive inside the routine', inside, 0);
  Chk('as-cast: dead after it returns', destroyed, 1);

  destroyed := 0;
  CallResultIsOwned(inside);
  Chk('call result: dead at f := nil', inside, 1);
  Chk('call result: still exactly one', destroyed, 1);

  destroyed := 0;
  LValueIsBorrowed(inside);
  Chk('lvalue: alive while g holds it', inside, 0);
  Chk('lvalue: dead after g := nil', destroyed, 1);

  destroyed := 0;
  UseAfterFreeShape;
  Chk('uaf shape: all nine destroyed', destroyed, 9);

  writeln;
  writeln('total ok ', pass, ' / ', pass + fail);
end.
