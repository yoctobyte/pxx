program test_rv32_low32_narrowing_keeps_64bit_answers;
{ Integer arithmetic is typed at 64 bits (decide-shift-operator-promotion-width).
  The riscv32 backend computes a binop in 32 bits when its consumer keeps only
  the low word (a store to a <= 4-byte integer) and that gives the same answer:
  + - * and or xor always, div/mod only when both operands are 32-bit by type
  and agree on signedness. Every line here must print what x86-64 prints.
  The interesting rows are the ones that must NOT narrow: a 64-bit dividend
  (`(a * b) div c` where a * b passes 2^31) and mixed signedness
  (`LongWord div Integer` divides signed in Int64). On the IDF profile the
  64-bit divisions that remain are libgcc calls (__divdi3 and friends). }
var
  a, b, c, r: Integer;
  u, v, w: LongWord;
  bt: Byte;
  wd: Word;
  q, q2: Int64;
  uq: QWord;
  i: Integer;

function Id(x: Integer): Integer;
begin
  Result := x;
end;

begin
  { wraparound at the store: identical either way }
  a := 2147483647; b := Id(1);
  r := a + b;              writeln('max+1 ', r);
  a := -2147483647 - 1;
  r := a - b;              writeln('min-1 ', r);
  a := 65536; b := 65536;
  r := a * b;              writeln('2^16*2^16 ', r);
  a := 123456789; b := 987654321;
  r := a * b + a - b;      writeln('mix ', r);
  r := (a xor b) and (a or b); writeln('logic ', r);

  { 32-bit div/mod, the edge cases of the hardware divide }
  a := -2147483647 - 1; b := Id(-1);
  r := a div b;            writeln('min div -1 ', r);
  r := a mod b;            writeln('min mod -1 ', r);
  a := -7; b := 2;
  r := a div b;            writeln('-7 div 2 ', r);
  r := a mod b;            writeln('-7 mod 2 ', r);
  a := 7; b := -2;
  r := a div b;            writeln('7 div -2 ', r);
  r := a mod b;            writeln('7 mod -2 ', r);

  { a 64-bit dividend must not narrow }
  a := 100000; b := 300000; c := Id(7);
  r := (a * b) div c;      writeln('wide dividend ', r);
  r := (a * b) mod c;      writeln('wide mod ', r);
  a := 2000000000;
  r := (a + a) div 3;      writeln('wide sum div ', r);

  { mixed signedness divides signed in Int64 }
  u := 4000000000; a := Id(-3);
  r := u div a;            writeln('LongWord div Integer ', r);
  r := u mod a;            writeln('LongWord mod Integer ', r);
  { both unsigned: divu }
  u := 4000000000; v := 7;
  w := u div v;            writeln('LongWord div LongWord ', w);
  w := u mod v;            writeln('LongWord mod LongWord ', w);
  { narrow types }
  bt := 250; wd := 65000; a := Id(-9);
  r := bt div a;           writeln('Byte div Integer ', r);
  r := wd mod a;           writeln('Word mod Integer ', r);
  bt := bt + 10;           writeln('Byte wrap ', bt);
  wd := wd * 2;            writeln('Word wrap ', wd);

  { Int64 division (libgcc on IDF, inline elsewhere) }
  q := 1000000000000; q2 := -7;
  writeln('i64 div ', q div q2);
  writeln('i64 mod ', q mod q2);
  uq := QWord(18000000000000000000);
  writeln('u64 div ', uq div 7);
  writeln('u64 mod ', uq mod 7);
  q := 0;
  for i := 1 to 20 do q := q + (Int64(i) * 1000000007) div i;
  writeln('loop ', q);
end.
