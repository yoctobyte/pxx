program test_i386_int64;

{ Full 64-bit by-value parameter passing: the callee must receive all 64 bits,
  not a truncated/sign-extended low dword. }
function addhi(v: Int64; k: Int64): Int64;
begin addhi := v + k; end;
function hidword(v: Int64): Int64;
begin hidword := v shr 32; end;


{ Focused Int64 oracle: shifts across the 32-bit boundary, high-dword
  constants, memory load/store of 64-bit values, and comparisons whose
  result depends on the high dword. Output must be identical to the
  x86-64 build. }

var
  a, b, c: Int64;
  i: Integer;
begin
  { high-dword constant survives store + load }
  a := 4831834837817753600;          { 0x430c6bf526340000 }
  writeln(a);

  { shr across the boundary }
  b := a shr 32;                     { 0x430c6bf5 = 1124416501 }
  writeln(b);
  b := a shr 40;                     { 0x430c6b   = 4393067 }
  writeln(b);
  b := a shr 63;                     { 0 }
  writeln(b);
  b := a shr 1;
  writeln(b);
  b := a shr 0;
  writeln(b);

  { shl across the boundary }
  c := 1;
  writeln(c shl 0);
  writeln(c shl 1);
  writeln(c shl 31);
  writeln(c shl 32);
  writeln(c shl 40);
  writeln(c shl 62);

  { and/or over high dwords }
  a := 4831834837817753600;
  writeln(a and 1124416501);
  writeln(a or 255);

  { comparisons that differ only in the high dword }
  a := 4294967296;                   { 1 shl 32 }
  b := 1;
  if a > b then writeln(1) else writeln(0);
  if b > a then writeln(1) else writeln(0);
  if a = b then writeln(1) else writeln(0);
  if a <> b then writeln(1) else writeln(0);

  { equality where the operands ARE equal (branch-true path) }
  a := 4294967296;
  b := 4294967296;
  if a = b then writeln(1) else writeln(0);
  if a <> b then writeln(1) else writeln(0);
  a := 0;
  if a = 0 then writeln(1) else writeln(0);
  a := 9223372036854775807;
  if a = 9223372036854775807 then writeln(1) else writeln(0);
  if a <= b then writeln(1) else writeln(0);
  if a >= b then writeln(1) else writeln(0);

  { ordered compares that cross the sign boundary (left negative, right >= 0):
    these exercise the high-dword sbb in left-right ordered compares. }
  a := -9;
  if a < 0 then writeln(1) else writeln(0);
  if a < 5 then writeln(1) else writeln(0);
  if a < -5 then writeln(1) else writeln(0);
  if a >= 0 then writeln(1) else writeln(0);
  if a >= -100 then writeln(1) else writeln(0);
  a := -4294967296;
  if a < 0 then writeln(1) else writeln(0);
  if a < 1 then writeln(1) else writeln(0);
  if a >= -4294967296 then writeln(1) else writeln(0);
  a := 9223372036854775807;     { Int64 max }
  if a < 0 then writeln(1) else writeln(0);
  if a > -1 then writeln(1) else writeln(0);
  a := -9223372036854775807;
  if a < 0 then writeln(1) else writeln(0);
  if a > 0 then writeln(1) else writeln(0);

  { add/sub that carry across the boundary }
  a := 4294967295;                   { 0xFFFFFFFF }
  b := a + 1;                        { 0x100000000 }
  writeln(b);
  c := b - 1;
  writeln(c);

  { negative Int64 }
  a := -1;
  writeln(a);
  a := -4294967296;
  writeln(a);

  { loop building a 64-bit accumulator }
  c := 0;
  for i := 1 to 40 do
    c := c + 1000000000;            { 40e9 > 2^32 }
  writeln(c);

  { full 64-bit by-value param passing (callee sees all 64 bits) }
  writeln(addhi(4831834837817753600, 1));
  writeln(hidword(4831834837817753600));     { high dword survives the call }
  writeln(addhi(-4294967296, 4294967296));   { -2^32 + 2^32 = 0 }
  writeln(hidword(1000000000000000));

  { multiply across the boundary }
  a := 1000000000;
  b := 1000000000;
  writeln(a * b);                   { 1e18 }
  a := 4294967296;
  writeln(a * 3);

  { signed div/mod }
  a := 1000000000000;
  b := 7;
  writeln(a div b);
  writeln(a mod b);
  a := -1000000000000;
  writeln(a div b);
  writeln(a mod b);
  a := 1000000000000;
  b := -7;
  writeln(a div b);
  writeln(a mod b);
  a := -1000000000000;
  b := -7;
  writeln(a div b);
  writeln(a mod b);

  { large / large }
  a := 9223372036854775807;          { Int64 max }
  b := 1000000007;
  writeln(a div b);
  writeln(a mod b);
end.
