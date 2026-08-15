program lib_random;
{ Unit test for lib/rtl/random. Track B. Build with the pinned stable.

  Determinism is the contract: a fixed seed yields a fixed sequence, and
  reseeding reproduces it exactly. The seeded stream is ALSO the cross-target
  oracle — the same bytes on x86-64, i386, aarch64 and arm32 — so a divergence
  here is a codegen bug in 64-bit shifts or multiplies, not a library one.
  (riscv32 cannot build this unit at all: the shared state's lock needs atomics
  the core has no instruction for. bug-a-riscv32-and-xtensa-have-no-atomic-codegen.)

  Tests the unit's DISTINCT surface — xoshiro256**, not the compiler's builtin
  Random/RandSeed, which is the legacy LCG and is not redefined here.

  The RandRange values changed on 2026-08-15 and the old ones were the buggy
  output: `mod` on a 31-bit draw is biased, measurably so (60.23% of draws into
  the low 43.17% of a 1.5e9 span), and it raised EDivByZero across the full
  Integer range. Masked rejection replaced it. If these numbers ever need
  changing again, that is a red flag, not a refresh. }
uses random;
var
  i, n: Integer;
  st: TRandomState;
  buf: array[0..31] of Byte;
  d: Double;
begin
  XoshiroSeed(1);
  for i := 1 to 8 do write(RandRange(1, 6), ' ');
  writeln;
  XoshiroSeed(1);                    { reseed -> identical line }
  for i := 1 to 8 do write(RandRange(1, 6), ' ');
  writeln;
  XoshiroSeed(42);
  for i := 1 to 5 do write(RandRange(0, 999), ' ');
  writeln;

  { unbiased across the FULL Integer range — this raised EDivByZero before,
    because hi-lo+1 wrapped Integer to 0 }
  XoshiroSeed(7);
  n := 0;
  for i := 1 to 200 do
    if (RandRange(Low(Integer), High(Integer)) >= Low(Integer)) then n := n + 1;
  writeln('fullrange ', n);

  { Int64 span, including the whole of Int64 where no rejection is possible }
  XoshiroSeed(3);
  for i := 1 to 3 do write(RandRange64(0, 1000000), ' ');
  writeln;
  XoshiroSeed(3);
  n := 0;
  for i := 1 to 100 do if RandRange64(Low(Int64), High(Int64)) <> 0 then n := n + 1;
  writeln('int64full ', n);
  writeln('degenerate ', RandRange(9, 9), ' ', RandRange64(7, 7), ' ', RandRange(10, 3));

  { [0,1) with a 53-bit significand }
  XoshiroSeed(11);
  n := 0;
  for i := 1 to 1000 do
  begin
    d := RandomDouble;
    if (d >= 0.0) and (d < 1.0) then n := n + 1;
  end;
  writeln('double ', n);

  { byte fill: deterministic from a seed, and never writes past n }
  XoshiroSeed(5);
  for i := 0 to 31 do buf[i] := 0;
  RandomBytes(buf, 12);
  for i := 0 to 11 do write(buf[i], ' ');
  n := 0;
  for i := 12 to 31 do if buf[i] <> 0 then n := n + 1;
  writeln('| past ', n);

  { private state: reproducible, and independent of the shared stream }
  RandomStateSeed(st, 99);
  for i := 1 to 3 do write(RandomStateRange(st, 1, 1000), ' ');
  writeln;
  RandomStateSeed(st, 99);
  for i := 1 to 3 do write(RandomStateRange(st, 1, 1000), ' ');
  writeln;
  RandomStateSeed(st, 99);
  write(RandomStateRange64(st, 0, 1000000), ' ');
  RandomStateSeed(st, 99);
  writeln(RandomStateRange64(st, 0, 1000000));
end.
