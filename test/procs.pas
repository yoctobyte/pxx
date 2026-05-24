program Procs;

function Factorial(n: Integer): Integer;
begin
  if n <= 1 then
    Factorial := 1
  else
    Factorial := n * Factorial(n - 1);
end;

function Fib(n: Integer): Integer;
begin
  if n <= 1 then
    Fib := n
  else
    Fib := Fib(n - 1) + Fib(n - 2);
end;

procedure PrintLine(x: Integer);
begin
  writeln(x);
end;

var i: Integer;

begin
  writeln('Factorials:');
  for i := 1 to 7 do
    PrintLine(Factorial(i));

  writeln('Fibonacci:');
  for i := 0 to 8 do
    PrintLine(Fib(i));
end.
