program lib_random;
{ Unit test for lib/rtl/random. Track B. Build with the pinned stable.
  Determinism is the contract: a fixed seed yields a fixed sequence, and
  reseeding reproduces it exactly. }
uses random;
var i: Integer;
begin
  RandSeed(1);
  for i := 1 to 8 do write(Random(6) + 1, ' ');
  writeln;
  RandSeed(1);                       { reseed -> identical line }
  for i := 1 to 8 do write(Random(6) + 1, ' ');
  writeln;
  RandSeed(42);
  for i := 1 to 5 do write(Random(1000), ' ');
  writeln;
end.
