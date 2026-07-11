{ SPDX-License-Identifier: 0BSD }
program Fib;
{ Portable call-heavy integer benchmark — naive recursive Fibonacci, the
  common Pascal subset BOTH pascal26 and FPC accept (no units). Stresses call
  overhead / prologue-epilogue / register save codegen rather than the float
  path nbody covers. Deterministic Int64 result → canary holds pxx-vs-fpc and
  across -O levels. }

var
  i, total: Int64;

function Fib(n: LongInt): Int64;
begin
  if n < 2 then
    Fib := n
  else
    Fib := Fib(n - 1) + Fib(n - 2);
end;

begin
  total := 0;
  for i := 1 to 8 do
    total := total + Fib(32);
  Writeln('fib ', total);
end.
