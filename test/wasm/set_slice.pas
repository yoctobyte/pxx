program SetSlice;

{ `x in [...]` — set membership, which is not a set.

  SPECIAL_IN is only emitted for an ALL-CONSTANT set literal; a variable member
  (`i in [j]`) lowers to a real 32-byte set through IR_DEFAULT_MEM and never
  reaches this path. So the subject here is the constant-literal form, which is
  what almost all real code writes and what 267 of compiler.pas's 431 refusal
  lines were waiting on.

  What a happy-path `i in [1,2,3]` would not catch:

    * RANGES. A member is either a constant or an IR_BLOCK carrying lo..hi. A
      build that read a range's node as a scalar would compare against the low
      bound alone and answer plausibly for everything below it.
    * MIXED members and ranges in one literal, in that order and the reverse.
    * BOUNDARIES. lo and hi are INCLUSIVE; an off-by-one at either end is one
      wrong answer out of seven and survives a small test.
    * THE EMPTY SET, which is always False and is the case an accumulator
      initialised wrongly gets wrong.
    * WIDTH. The comparison happens at the test value's own width. i386 moves
      the value into eax and compares 32-bit, so `q in [1,2,3]` with
      q = 2^32+1 answers TRUE there and FALSE on x86-64 — measured, both run.
      This slice asserts the x86-64 answer. }

type TCol = (Red, Green, Blue, Puce);
var i: Integer; c: Char; e: TCol; q: Int64; n: Integer;
begin
  for i := 0 to 6 do write(i in [1,2,3], ' ');      writeln;
  for i := 0 to 6 do write(i in [2..4], ' ');       writeln;
  for i := 0 to 6 do write(i in [0, 2..3, 6], ' '); writeln;
  for i := 0 to 6 do write(i in [2..3, 0, 6], ' '); writeln;
  writeln('empty=', 5 in []);

  for c := 'a' to 'e' do write(c in ['a','c'..'d'], ' '); writeln;
  writeln('upper=', 'Q' in ['a'..'z'], ' ', 'q' in ['a'..'z']);

  e := Blue;  writeln('enum=', e in [Green, Blue], ' ', e in [Red, Puce]);

  { a single-element range, where lo = hi }
  for i := 2 to 4 do write(i in [3..3], ' '); writeln;

  { 2^32 + 1: FALSE, and TRUE would mean the comparison was truncated to 32 bits }
  q := 4294967297;
  writeln('wide=', q in [1, 2, 3]);

  n := 0;
  for i := 0 to 255 do if i in [10..20, 200] then n := n + 1;
  writeln('count=', n);
end.
