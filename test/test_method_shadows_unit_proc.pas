program test_method_shadows_unit_proc;

{ A bare call inside a method to another method of the same class must bind
  to the class's own method (Self.method), even when a same-name PLAIN PROC
  exists — from a uses'd unit (sysutils.Move vs TGame.Move, the adventure
  symptom) or from the program's own top level. FPC: innermost scope wins.
  See bug-implicit-self-method-loses-to-unit-proc. }

uses sysutils;  { has the 3-arg Move }

var plainHits: Integer;

procedure Bump(v: Integer);      { same-file plain proc, arity matches method }
begin
  plainHits := plainHits + v;    { must NOT run from inside TGame }
end;

type
  TGame = class
    pos: Integer;
    steps: Integer;
    procedure Move(d: Integer);          { 1-arg, vs sysutils' 3-arg Move }
    procedure Bump(v: Integer);          { same name AND arity as plain Bump }
    function Tick: Integer; virtual;     { virtual -> exercise the VMT path }
    procedure Run;
  end;

function Tick: Integer;          { plain function shadowed by the method }
begin
  Tick := -999;
end;

procedure TGame.Move(d: Integer);
begin
  pos := pos + d;
end;

procedure TGame.Bump(v: Integer);
begin
  steps := steps + v;
end;

function TGame.Tick: Integer;
begin
  Tick := pos * 10;
end;

procedure TGame.Run;
begin
  Move(5);                   { Self.Move, not sysutils.Move -> pos = 5 }
  Bump(3);                   { Self.Bump, not plain Bump    -> steps = 3 }
  writeln('tick=', Tick);    { Self.Tick (virtual), not plain Tick -> 50 }
end;

var
  g: TGame;
  a, b: array[0..3] of Integer;
begin
  plainHits := 0;
  g := TGame.Create;
  g.Run;
  writeln('pos=', g.pos);
  writeln('steps=', g.steps);
  writeln('plainHits=', plainHits);   { 0 -- plain Bump never ran }
  a[0] := 7; a[1] := 8;
  Move(a, b, 2 * SizeOf(Integer));    { outside a method: plain Move still works }
  writeln('b0=', b[0], ' b1=', b[1]);
  Bump(2);                            { outside a method: plain Bump }
  writeln('plainHits2=', plainHits);  { 2 }
  g.Free;
end.
