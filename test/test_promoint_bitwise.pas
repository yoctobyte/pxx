{ Promotable-int bitwise ops with Python two's-complement semantics.
  Drives the uforth DO/LOOP unsigned-mask idiom that motivated them. }
program test_promoint_bitwise;
var mask, a, b: PromoInt;
begin
  mask := 18446744073709551615;   { 2^64-1 }

  { AND with an all-ones mask reinterprets a negative as unsigned 64-bit }
  a := 4; a := a - 5;             { -1 }
  a := a and mask;
  writeln(a);                     { 18446744073709551615 }

  b := 5; b := b - 5;            { 0 }
  b := b and mask;
  writeln(b);                     { 0 }

  { unsigned compare after masking (uforth _loop_crossed) }
  if a > b then writeln('crossed') else writeln('not');   { crossed }

  { shift-left past 64 bits (Pascal `shr` lexes as an identifier, so the shift
    RIGHT path is exercised by the NilPy `>>` tests instead) }
  a := 1; a := a shl 64;
  writeln(a);                     { 18446744073709551616 }

  { OR / XOR }
  a := 240; b := 15;
  writeln(a or b);                { 255 }
  writeln(a xor b);               { 255 }
  a := 255; b := 15;
  writeln(a and b);               { 15 }
end.
