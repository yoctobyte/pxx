{ SPDX-License-Identifier: MPL-2.0 }
program test_for_bound_reads_a_counter_that_shadows_a_const;
{ `for n := 1 to N` where a LOCAL `n` hides a global `const N`: Pascal is
  case-insensitive, so the bound is the counter itself, read before the loop
  assigns it. FPC and pxx agree on the value (the loop runs to whatever the
  counter held) and neither complained, which is how examples/parallel/
  collatz.pas printed `total steps = 0`. pxx now WARNS on the shadow shape
  only: Legit reads its own initialised counter with no outer namesake and
  must stay silent. The Makefile row counts the warnings by line. }
const N = 100;
procedure Shadow;
var n: Integer; t: Int64;
begin
  n := 4; t := 0;
  for n := 1 to N do t := t + n;            { line 15: warns, end bound }
  writeln('shadow ', t);
end;
procedure Legit;
var i: Integer; t: Int64;
begin
  i := 3; t := 0;
  for i := i to 5 do t := t + i;
  writeln('legit ', t);
end;
procedure Other;
var i: Integer; t: Int64;
begin
  t := 0;
  for i := 1 to N do t := t + i;
  writeln('other ', t);
end;
begin
  Shadow; Legit; Other;
end.
