program TestStacklessGen;
{ Stackless generators: `; generator; stackless;` — a state-machine transform,
  no coroutine stack, no asm. Runs on every target. Library-only feature (slgen
  unit); never used in compiler.pas. Same surface as the stackful backend. }
uses slgen;

function Squares(n: Integer): Integer; generator; stackless;
var i: Integer;
begin
  for i := 1 to n do yield i * i;
end;

function Range(lo, hi: Integer): Integer; generator; stackless;
var i: Integer;
begin
  for i := lo to hi do yield i;
end;

function CountDown(n: Integer): Integer; generator; stackless;
var i: Integer;
begin
  for i := n downto 1 do yield i;
end;

{ while-loop + if (state machine over both) }
function EvensUpTo(n: Integer): Integer; generator; stackless;
var i: Integer;
begin
  i := 0;
  while i <= n do
  begin
    if (i mod 2) = 0 then yield i;
    i := i + 1;
  end;
end;

{ straightline: several yields in sequence, no loop }
function Three: Integer; generator; stackless;
begin
  yield 10;
  yield 20;
  yield 30;
end;

{ yield inside a case statement: single labels, a range, a multi-yield branch,
  else, and a top-level yield after the case (chess GenMoves' shape).
  See feature-stackless-generator-yield-in-case. }
function CaseGen(n: Integer): Integer; generator; stackless;
begin
  case n of
    1: yield 10;
    2: begin yield 20; yield 21; end;
    3..5: yield 30;
  else
    yield 99;
  end;
  yield 100 + n;
end;

{ case nested in a for loop, yields split per branch }
function LoopCase(n: Integer): Integer; generator; stackless;
var i: Integer;
begin
  for i := 1 to n do
    case i mod 3 of
      0: yield i * 100;
      1: yield i;
    else
      yield i * 10;
    end;
end;

var x, s: Integer;
begin
  for x in Squares(5) do write(x, ' ');         { 1 4 9 16 25 }
  writeln;

  s := 0;
  for x in Range(3, 7) do s := s + x;
  writeln(s);                                    { 25 }

  for x in CountDown(5) do write(x, ' ');        { 5 4 3 2 1 }
  writeln;

  for x in EvensUpTo(9) do write(x, ' ');        { 0 2 4 6 8 }
  writeln;

  for x in Three do write(x, ' ');               { 10 20 30 }
  writeln;

  { sequential reuse: instance freed at exhaustion, fresh each loop }
  for x in Range(1, 3) do write(x, ' ');         { 1 2 3 }
  writeln;

  for s := 0 to 6 do
    for x in CaseGen(s) do write(x, ' ');        { 99 100 10 101 20 21 102 30 103 30 104 30 105 99 106 }
  writeln;

  for x in LoopCase(6) do write(x, ' ');         { 1 20 300 4 50 600 }
  writeln;
end.
