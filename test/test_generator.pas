program TestGenerator;
{ Stackful generators: `; generator;` routine + `yield` + `for x in Gen(args)`.
  Library-only feature (coroutine unit); never used in compiler.pas. }
uses coroutine;

function Squares(n: Integer): Integer; generator;
var i: Integer;
begin
  for i := 1 to n do yield i * i;
end;

function Range(lo, hi: Integer): Integer; generator;
var i: Integer;
begin
  for i := lo to hi do yield i;
end;

function Fibs(n: Integer): Integer; generator;
var a, b, t, k: Integer;
begin
  a := 0; b := 1;
  for k := 1 to n do begin yield a; t := a + b; a := b; b := t; end;
end;

var x, s: Integer;
begin
  for x in Squares(5) do write(x, ' ');        { 1 4 9 16 25 }
  writeln;

  s := 0;
  for x in Range(3, 7) do s := s + x;
  writeln(s);                                   { 25 }

  for x in Fibs(8) do write(x, ' ');            { 0 1 1 2 3 5 8 13 }
  writeln;

  { sequential reuse: stack/instance freed at exhaustion, fresh each loop }
  for x in Range(1, 3) do write(x, ' ');        { 1 2 3 }
  writeln;
end.
