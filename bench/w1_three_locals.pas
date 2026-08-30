program W1ThreeLocals;
{ The `three.pas` of `feature-opt-o3-register-pressure` (W1) -- three hot
  locals in one loop, which is the shape the whole optimization campaign is
  aimed at: `i` (for counter), `j` (temp), `s` (accumulator), all candidates for
  the four residency registers r12..r15.

  COMMITTED 2026-08-30, at slice 10, because the original never was. It lived in
  /tmp across a dozen sessions and was gone by the time slice 10 wanted it, so
  the file below is a RECREATION from the campaign log's description -- and it
  is measurably not the same program (its loop body is 21 instructions at -O3
  where the log's last recorded figure was 17). Two benchmarks with one name
  are two benchmarks: the running "18 -> 17 -> ..." chain in that log stops at
  slice 9 and is NOT continued on this file. What a slice may quote from here is
  a DELTA measured between two compilers built at the same HEAD, the baseline
  being HEAD with only that slice's hunk reverted.

  Usage:
    pxx -O2 bench/w1_three_locals.pas /tmp/w1o2 && time /tmp/w1o2
    pxx -O3 bench/w1_three_locals.pas /tmp/w1o3 && time /tmp/w1o3
  Both must print the same line; -O3 is the one being measured.

  Nothing in the Makefile runs this. It is a measuring stick, not a test -- the
  correctness assertions for the passes it prices live in test/. }

var
  g: Int64;

function Run(n: LongInt): Int64;
var
  i, j: LongInt;
  s: Int64;
begin
  s := 0;
  for i := 1 to n do
  begin
    j := i xor Integer(s and 65535);
    s := s + j - (i shr 1);
  end;
  Run := s;
end;

begin
  g := Run(20000000);
  WriteLn('s=', g);
end.
