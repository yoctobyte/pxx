program test_rv32_compare_in_32_bits;
{ riscv32 does a comparison in 32 bits when both sides are 32-bit by type (an
  integer, Char or Boolean of at most 4 bytes) or constants in range, extended
  the same way -- signed both, or unsigned both. Everything else keeps the
  64-bit pair compare. The rows below are the ones that tell the two apart:
  a LongWord at or above 2^31 against constants (unsigned, even when the
  constant is Int64-typed), Integer against negative constants, Char and
  Boolean, mixed Integer/LongWord (must stay 64-bit: -1 < 4000000000), and
  `i < n - 1` with n = Low(Integer), where n - 1 is Int64 and does not wrap.
  Values come through globals and a function so nothing folds. Prints one
  line per group; the whole output is compared with x86-64. }
{$mode objfpc}
var
  lw, lw2: LongWord;
  i, j, n: Integer;
  si: SmallInt;
  w: Word;
  by: Byte;
  sh: ShortInt;
  c, d: Char;
  b, b2: Boolean;
  s: AnsiString;
  q: Int64;

function B2S(x: Boolean): Char;
begin
  if x then Result := '1' else Result := '0';
end;

function Id(v: Integer): Integer;
begin
  Result := v;
end;

procedure Six(a, z: Boolean; x, y, u, v: Boolean);
begin
  write(B2S(a), B2S(z), B2S(x), B2S(y), B2S(u), B2S(v), ' ');
end;

begin
  { LongWord >= 2^31: an unsigned compare in 32 bits, or 64 }
  lw := $80000000; lw2 := $FFFFFFFF;
  Six(lw > 0, lw < 1, lw = $80000000, lw >= 2147483648, lw > 2147483647, lw <> $80000000);
  Six(lw2 > lw, lw < lw2, lw2 = 4294967295, lw2 >= lw, lw2 <= lw, lw2 <> lw);
  q := 4294967295;
  Six(lw2 = q, lw < q, lw2 > q, lw > 100, lw < 100, lw2 > $7FFFFFFF);
  writeln;
  { Integer against negative constants and each other }
  i := -5; j := 3; n := Low(Integer);
  Six(i < 0, i > -6, i = -5, i <= -5, i >= -4, i <> -5);
  Six(i < j, j > i, n < i, n = -2147483648, n <= -2147483648, i > n);
  Six(Id(i) < Id(j), Id(n) > 0, Id(j) >= 3, Id(i) = Id(-5), Id(n) < -2147483647, Id(0) <> 0);
  writeln;
  { mixed signedness must keep the 64-bit answer }
  Six(i < lw, lw > i, -1 < lw, j < lw2, Id(-1) < lw2, n < lw);
  Six(i = lw, n <> lw, Int64(i) < lw, lw2 > j, lw2 > Id(-1), i < LongWord(1));
  writeln;
  { i < n - 1 at the bottom of Integer: n - 1 is Int64, no wrap }
  n := Low(Integer); i := 0;
  Six(i < n - 1, i > n - 1, n - 1 < n, n > n - 1, n + 0 = n, Id(n) - 1 < Id(n));
  n := High(Integer);
  Six(i < n + 1, n + 1 > n, n + 1 > 0, n < n + 1, Id(n) + 1 > 0, n + 1 = 2147483648);
  writeln;
  { Char and Boolean }
  s := 'a 9~'#200; c := s[5]; d := s[1];
  Six(s[2] = ' ', s[1] <> ' ', s[3] >= '0', s[3] <= '9', c > '~', c > d);
  Six(Ord(c) >= 128, Ord(c) > 127, Ord(c) = 200, Ord(d) < 98, Ord(s[2]) = 32, c < #201);
  b := True; b2 := False;
  Six(b = True, b2 = False, b > b2, b2 < b, b <> b2, Ord(b) = 1);
  writeln;
  { narrow kinds at their edges }
  si := -32768; w := 65535; by := 255; sh := -128;
  Six(si < 0, si < -32767, w > 65534, w > si, by > sh, sh < -127);
  Six(by = 255, w = 65535, sh = -128, si = -32768, by > 0, w < si);
  writeln;
  writeln('done');
end.
