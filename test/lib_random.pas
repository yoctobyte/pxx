program lib_random;
{ Unit test for lib/rtl/random. Track B. Build with the pinned stable.
  Determinism is the contract: a fixed seed yields a fixed sequence, and
  reseeding reproduces it exactly. Tests the unit's DISTINCT surface — xoshiro
  (XoshiroSeed / RandRange / Random64). The System PRNG (Random/RandSeed) is a
  compiler built-in and is not redefined here (see the unit header). }
uses random;
var i: Integer;
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
end.
