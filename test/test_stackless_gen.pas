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
end.
