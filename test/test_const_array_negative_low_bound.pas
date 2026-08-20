{ A typed constant (and var) ARRAY whose low bound is negative must place its
  initializer values at the right slots. Every element with a NEGATIVE index was
  written to the array's BASE instead: `array[-2..2] of Integer =
  (10,20,30,40,50)` stored 20 at slot 0 (the -2 element having been overwritten
  by the -1 one), nothing at slot 1, and the rest correctly.

  The cause was a sentinel living in the value space: PendingInitElem carries
  the element's array INDEX with -1 meaning "not an element", and the emitter
  asked `>= 0` before building the index node. A Pascal array index can be
  negative, so a real element answered the sentinel's question.

  A low bound of exactly -1 is the benign case — the one misplaced element lands
  on slot 0, which is where it belonged — and is why this survived: it is the
  bound most code uses when it uses a negative one at all. It is asserted here
  precisely because it CANNOT fail.

  Values are read back through a pointer at the base as well as by index, so a
  failure says whether the data or the indexing is wrong. Every expected value
  is `fpc -O- -Mobjfpc`'s.
  bug-p-typed-const-array-with-a-negative-low-bound-writes-to-its-base }
program test_const_array_negative_low_bound;
{$mode objfpc}{$H+}

const
  A2: array[-2..2] of Integer = (10, 20, 30, 40, 50);
  A5: array[-5..-3] of Integer = (1, 2, 3);
  B1: array[-2..0] of Byte    = (7, 8, 9);
  A1: array[-1..1] of Integer = (1, 2, 3);
  P0: array[0..2] of Integer  = (4, 5, 6);

var
  vA: array[-2..2] of Integer = (10, 20, 30, 40, 50);
  ok, total, k: Integer;
  pi: ^Integer; pb: ^Byte;

procedure Chk(const what: string; got, want: Integer);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got ', got, ' want ', want);
end;

procedure LocalConst;
const
  L2: array[-2..2] of Integer = (60, 70, 80, 90, 100);
var i: Integer;
begin
  { a routine-LOCAL typed constant goes through the other emitter }
  for i := -2 to 2 do Chk('local', L2[i], 60 + (i + 2) * 10);
end;

begin
  ok := 0; total := 0;

  { by index }
  for k := -2 to 2 do Chk('A2', A2[k], 10 + (k + 2) * 10);
  for k := -5 to -3 do Chk('A5', A5[k], k + 6);
  for k := -2 to 0 do Chk('B1', B1[k], k + 9);
  for k := -1 to 1 do Chk('A1', A1[k], k + 2);
  for k := 0 to 2 do Chk('P0', P0[k], k + 4);
  for k := -2 to 2 do Chk('vA', vA[k], 10 + (k + 2) * 10);

  { and as raw memory from the base, so a wrong SLOT cannot hide behind a
    matching wrong index }
  pi := @A2[-2];
  for k := 0 to 4 do Chk('A2mem', pi[k], 10 + k * 10);
  pi := @A5[-5];
  for k := 0 to 2 do Chk('A5mem', pi[k], k + 1);
  pb := @B1[-2];
  for k := 0 to 2 do Chk('B1mem', pb[k], k + 7);

  LocalConst;

  writeln('total ok ', ok, ' / ', total);
end.
