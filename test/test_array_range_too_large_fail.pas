{ %fail }
{ `array[0..High(PtrUInt)] of Byte` -- FPC's own tarray5.pp, whose comment is
  "This shouldn't be allowed, the number of elements doesn't fit in the address
  range". pxx accepted it, allocated nothing, and let the program index into
  whatever followed.

  Two separate readings had to be closed, and the second is the interesting one:
  the bound is UNSIGNED, so it arrives at the array parser as the bit pattern
  -1 and looks like an ordinary negative bound -- `array[0..-1]`, an empty
  array, perfectly legal. Only the KIND separates 2^64-1 from -1, which is why
  this could not be checked before the const evaluator carried unsignedness.

  The signed spelling `array[0..High(Int64)]` had the same hole open the whole
  time and is rejected now too.
  feature-p-const-evaluator-carries-unsigned-64-bit }
program test_array_range_too_large_fail;
var
  mem: array[0..High(PtrUInt)] of Byte;
begin
  mem[0] := 1;
end.
