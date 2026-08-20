{ An interface-returning CALL assigned to an interface destination handed the
  SAME reference to two owners.

  Such a call materialises its result into a hidden caller-side temp, and that
  temp is an ordinary skLocal COM-interface symbol -- so the scope-exit cleanup
  releases it. The assignment then copied the fat pointer out of that temp with a
  RAW record copy, no retain, because a call result is already OWNED (+1 from the
  callee) and retaining it would over-count. Correct reasoning, wrong conclusion:
  the destination did not need a RETAIN, it needed the temp to stop owning.

    f := Mk;       { temp: +1.  f: aliases it, uncounted  }
    f := nil;      { refcount 0 -- the object is FREED     }
                   { scope exit: releases the temp, on freed memory }

  With ONE object that stale release reads harmless garbage, nothing is observed,
  and the destructor counts even match FPC exactly -- which is why this sat here.
  Put TWO of them in a local dynamic array and the freed blocks are recycled
  between the two releases:

    SetLength(d, 2); d[0] := Mk; d[1] := Mk; d[0] := nil; d[1] := nil;
                   { SIGSEGV at scope exit }

  One element, a constructor instead of a function, or a global array all ran
  clean, which is the matrix that pinned it to the result temp.

  The fix makes the move a move: hand the reference over, then NIL the temp so
  its scope-exit release is a no-op. The destination's old value is released
  after the call is evaluated, which is safe under aliasing because the temp
  holds a reference to the new value throughout -- `f := Mk` returning the object
  f already holds cannot drop it to zero there, and that case is checked below.

  Every expectation is `fpc -O- -Mobjfpc` 3.2.2's.
  bug-a-two-function-result-interfaces-into-a-local-dyn-array-segfault }
program test_interface_call_result_move;
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

var
  destroyed, pass, fail: Integer;

constructor TFoo.Create(const n: string); begin inherited Create; fN := n; end;
destructor TFoo.Destroy; begin Inc(destroyed); inherited Destroy; end;
function TFoo.Name: string; begin Result := fN; end;

function Mk(const n: string): IFoo; begin Result := TFoo.Create(n); end;
function Passthru(a: IFoo): IFoo; begin Result := a; end;

procedure Chk(const what: string; got, want: Integer);
begin
  if got = want then begin Inc(pass); writeln('ok   ', what, ' = ', got); end
  else begin Inc(fail); writeln('FAIL ', what, ' = ', got, ' want ', want); end;
end;

{ the crash: two call results into a LOCAL dynamic array }
procedure TwoIntoDynArray;
var d: array of IFoo;
begin
  SetLength(d, 2);
  d[0] := Mk('a');
  d[1] := Mk('b');
  d[0] := nil;
  d[1] := nil;
end;

{ same, via a loop, and more of them so blocks are certainly recycled }
procedure ManyIntoDynArray(n: Integer);
var d: array of IFoo; i: Integer;
begin
  SetLength(d, n);
  for i := 0 to n - 1 do d[i] := Mk('m');
  for i := 0 to n - 1 do d[i] := nil;
end;

{ a scalar local -- always "worked", in that it never faulted }
procedure ScalarLocal;
var f: IFoo;
begin
  f := Mk('s');
  f := nil;
end;

{ overwriting a destination that already holds an object: the OLD one must be
  released exactly once, and the new one must survive }
function Overwrite: Boolean;
var f: IFoo;
begin
  f := Mk('old');
  f := Mk('new');
  Result := f.Name = 'new';
  f := nil;
end;

{ the aliasing case the release order has to be safe for: the call RETURNS the
  object the destination already holds }
function SelfReturning: Boolean;
var f: IFoo;
begin
  f := Mk('self');
  f := Passthru(f);
  Result := f.Name = 'self';
  f := nil;
end;

{ a static array element and a record field destination }
type TRec = record f: IFoo; end;
function OtherDestinations: Boolean;
var arr: array[0..1] of IFoo; r: TRec;
begin
  arr[0] := Mk('p'); arr[1] := Mk('q');
  r.f := Mk('t');
  Result := (arr[0].Name = 'p') and (arr[1].Name = 'q') and (r.f.Name = 't');
  arr[0] := nil; arr[1] := nil; r.f := nil;
end;

begin
  pass := 0; fail := 0;

  destroyed := 0; TwoIntoDynArray;
  Chk('two call results into a local dyn array', destroyed, 2);

  destroyed := 0; ManyIntoDynArray(16);
  Chk('sixteen call results into a local dyn array', destroyed, 16);

  destroyed := 0; ScalarLocal;
  Chk('call result into a scalar local', destroyed, 1);

  destroyed := 0;
  Chk('overwrite keeps the new object', Ord(Overwrite), 1);
  Chk('overwrite released both', destroyed, 2);

  destroyed := 0;
  Chk('call returning the destination survives', Ord(SelfReturning), 1);
  Chk('self-returning released exactly once', destroyed, 1);

  destroyed := 0;
  Chk('static element and record field destinations', Ord(OtherDestinations), 1);
  Chk('those three released', destroyed, 3);

  writeln;
  writeln('total ok ', pass, ' / ', pass + fail);
end.
