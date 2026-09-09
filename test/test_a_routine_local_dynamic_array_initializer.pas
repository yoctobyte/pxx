program test_a_routine_local_dynamic_array_initializer;
{$mode objfpc}{$H+}
{ `var v: array of Integer = (1, 2, 3);` inside a routine was refused with
  `a routine-local dynamic-array initializer is not supported yet`. The global
  spelling and the routine-local FIXED array both already worked.

  ROW 1 IS THE CONTROL AND IT MUST NOT MOVE. The global spelling runs the same
  element loop, and the fix is a change to WHICH TABLE that loop writes into --
  so a regression here shows up as the global case breaking, not the local one.

  ROW 2 IN ITS SECOND PRINTING is the row that catches the real hazard. The
  first attempt registered the local declaration in the FILE-SCOPE table,
  because the "which table" flag was read further down the procedure than the
  dynamic arm that needed it, so the arm saw the PREVIOUS declaration group's
  value. Program entry then assigned into a symbol index belonging to a
  rolled-back routine scope: `Length(v)` answered 0 and the first index
  SEGFAULTED. Every row is printed twice, from two calls, because an
  initializer that runs once at program entry and an initializer that runs on
  each entry to the routine are indistinguishable from a single call.

  ROW 6 IS WHY LENGTH ALONE IS NOT ENOUGH, which the ticket's gate demanded: a
  dynamic array that ends up EMPTY still compiles and still indexes in range
  for zero iterations, so every row here reads back an ELEMENT as well as a
  length. Row 7 writes one afterwards, because a var initializer is a writable
  starting value and not a constant.

  ROW 5 is the OTHER kind-10 site -- a FIXED array of DYNAMIC arrays, one
  pending init per element -- which was refused by the same assertion and is
  fixed by the same deletion. Its first two elements are nil and `()`, so it
  also asserts that an empty element list is length 0 rather than absent.

  Byte-identical to fpc 3.2.2 -Mobjfpc on all seven rows, and on i386 /
  aarch64 / arm32 / riscv32 under qemu. The DELPHI bracket spelling
  (`= [4, 5]`) is a separate surface: fpc refuses it under -Mobjfpc and accepts
  it under -Mdelphi, where pxx agrees with it. Not in this file because the two
  spellings cannot share a mode.
  feature-p-a-routine-local-dynamic-array-initializer }
var g: array of Integer = (10, 20, 30);
procedure P;
var
  a: array of Integer = (1, 2, 3);
  b: array of Integer = (4, 5);
  c: array of Integer = nil;
  d: array[0..2] of array of Integer = (nil, (), (7, 8, 9));
  s: array of string = ('a', 'bb');
begin
  WriteLn('2 local     ', Length(a), ' ', a[0], ' ', a[2]);
  WriteLn('3 second    ', Length(b), ' ', b[0], ' ', b[1]);
  WriteLn('4 nil       ', Length(c));
  WriteLn('5 of dyn    ', Length(d[0]), ' ', Length(d[1]), ' ', Length(d[2]), ' ', d[2][2]);
  WriteLn('6 strings   ', Length(s), ' ', s[0], ' ', s[1]);
  a[1] := 99;
  WriteLn('7 writable  ', a[1]);
end;
procedure Q;
var v: array of Integer = (41, 42);
begin
  WriteLn('8 other proc ', Length(v), ' ', v[0], ' ', v[1]);
end;
begin
  WriteLn('1 global    ', Length(g), ' ', g[0], ' ', g[2]);
  P; Q; P;
end.
