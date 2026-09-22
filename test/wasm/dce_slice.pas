{ The subject is --dce on wasm32, so this fixture is chosen for what it makes
  REACHABLE rather than for what it computes.

  A virtual call on wasm is a `call_indirect`, which names a TYPE and not a
  function, so the only thing that keeps an override alive is its presence in
  the element segment. That is the root category most likely to be wrong, and
  it is the one a hello world cannot exercise at all: the override is called
  through a base-class reference, so no direct `call` edge names it anywhere in
  the module.

  The printed values are 49 and a message. 49 is not a default, a zero, an
  empty aggregate or a pointer width, so a row asserting it cannot pass on a
  blank -- and a dropped override would not print 0, it would trap. }
program dce_slice;

type
  TShape = class
    function Area: Integer; virtual; abstract;
    function Name: AnsiString; virtual;
  end;

  TSquare = class(TShape)
    S: Integer;
    function Area: Integer; override;
    function Name: AnsiString; override;
  end;

function TShape.Name: AnsiString;
begin
  Name := 'shape';
end;

function TSquare.Area: Integer;
begin
  Area := S * S;
end;

function TSquare.Name: AnsiString;
begin
  Name := 'square';
end;

{ Never called, never address-taken, never exported by anything a root
  reaches. If --dce keeps this, the pass is not doing its job; if --dce drops
  something the program needs, the output below changes. }
function NeverReached(x: Integer): Integer;
begin
  NeverReached := x * 3 + 1;
end;

var
  sq: TSquare;
  o: TShape;
begin
  sq := TSquare.Create;
  sq.S := 7;
  { through the BASE reference, so the override is reached only by
    call_indirect and only survives via the element segment }
  o := sq;
  WriteLn('area=', o.Area);
  WriteLn('name=', o.Name);
  sq.Free;
end.
