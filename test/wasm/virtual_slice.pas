{ SPDX-License-Identifier: MPL-2.0 }
{ Virtual-dispatch slice oracle — WRITTEN AHEAD OF ITS RUNTIME, deliberately.

  A VMT slot holds a table index here, and reading one is an i32 load at
  slot*8 from [Self]. Getting the stride wrong reads a NEIGHBOURING method,
  which — for a hierarchy where the methods share a signature, as they do
  below — dispatches to the wrong routine and validates perfectly.

  So this slice is a differential and it cannot be run on the wasm side yet:
  every one of these functions begins with a class instantiation, which is a
  heap allocation, and the heap is a later phase. What the check DOES assert is
  that the module compiles, that no body here is emitted as `unreachable` for a
  dispatch reason, and that it validates — which proves the VMT path emits and
  type-checks. It does not prove it dispatches, and the check says so rather
  than implying otherwise by being green.

  When the heap lands, this file does not change: the check gains its node run
  and the native output it already produces becomes the oracle.

    Legs/Speak  three levels, an override at each, called through the BASE
                type so nothing static can answer.
    Describe    NOT virtual, and it calls two virtual methods on Self — so the
                dispatch happens inside a routine reached by a direct call.
    inherited   TPenguin.Speak calls its parent DIRECTLY while the VMT also
                names that routine: the same method reached both ways in one
                program, which is what would catch the two paths disagreeing.
    TotalSpeak  a virtual call in a loop over an array of different classes:
                dispatch has to follow the instance, not the loop. }
program VirtualSlice;

type
  TAnimal = class
    function Legs: Integer; virtual;
    function Speak: Integer; virtual;
    function Describe: Integer;
  end;

  TBird = class(TAnimal)
    function Legs: Integer; override;
    function Speak: Integer; override;
  end;

  TPenguin = class(TBird)
    function Speak: Integer; override;
  end;

var
  A: TAnimal;
  B: TBird;
  P: TPenguin;

function TAnimal.Legs: Integer;
begin Legs := 4; end;

function TAnimal.Speak: Integer;
begin Speak := 100; end;

{ Not virtual: it calls two virtual methods on Self, so the dispatch happens
  inside a routine reached by a direct call. }
function TAnimal.Describe: Integer;
begin Describe := Legs * 1000 + Speak; end;

function TBird.Legs: Integer;
begin Legs := 2; end;

function TBird.Speak: Integer;
begin Speak := 200; end;

function TPenguin.Speak: Integer;
begin Speak := inherited Speak + 7; end;

function AnimalLegs: Integer;
begin
  A := TAnimal.Create;
  AnimalLegs := A.Legs;
end;

function BirdLegs: Integer;
begin
  B := TBird.Create;
  BirdLegs := B.Legs;
end;

{ Through the BASE type: the static type is TAnimal, the instance is not. }
function BirdSpeakViaBase: Integer;
var x: TAnimal;
begin
  x := TBird.Create;
  BirdSpeakViaBase := x.Speak;
end;

function PenguinSpeak: Integer;
var x: TAnimal;
begin
  x := TPenguin.Create;
  PenguinSpeak := x.Speak;
end;

function BirdDescribe: Integer;
var x: TAnimal;
begin
  x := TBird.Create;
  BirdDescribe := x.Describe;
end;

function PenguinDescribe: Integer;
var x: TAnimal;
begin
  x := TPenguin.Create;
  PenguinDescribe := x.Describe;
end;

function TotalSpeak: Integer;
var t, i: Integer; z: array[0..2] of TAnimal;
begin
  z[0] := TAnimal.Create;
  z[1] := TBird.Create;
  z[2] := TPenguin.Create;
  t := 0;
  for i := 0 to 2 do t := t + z[i].Speak;
  TotalSpeak := t;
end;

{$ifndef WASM_NOMAIN}
begin
  writeln(AnimalLegs);
  writeln(BirdLegs);
  writeln(BirdSpeakViaBase);
  writeln(PenguinSpeak);
  writeln(BirdDescribe);
  writeln(PenguinDescribe);
  writeln(TotalSpeak);
end.
{$else}
begin
end.
{$endif}
