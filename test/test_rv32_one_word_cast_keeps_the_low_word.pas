program test_rv32_one_word_cast_keeps_the_low_word;
{ On riscv32 Chr(), Integer(), LongWord(), Char() and Boolean() of an
  integer expression evaluate it for its low word only, so `Chr(Ord('0') +
  d)` adds in 32 bits. The answers must be the truncation of the full value:
  sums that carry past 32 bits, and negative values. (Ord of an Int64 is
  left out: the frontend types it Integer, so every 32-bit target truncates
  it while x86-64 and FPC keep 64 bits -- a separate, older defect.) Prints
  the same on x64. }
{$mode objfpc}
var
  buf: array[0..15] of Char;
  i, p: Integer;
  big, x: Int64;
  w: LongWord;
  q: QWord;
  s: string;

begin
  p := 0;
  w := 4000000000;
  repeat
    buf[p] := Chr(Ord('0') + Integer(w mod 10));
    w := w div 10;
    Inc(p);
  until w = 0;
  s := '';
  for i := p - 1 downto 0 do s := s + buf[i];
  writeln('digits: ', s);
  big := $1FFFFFFF0;
  for i := 0 to 3 do
  begin
    x := big + i * 7;
    writeln(i, ': ', Integer(x + 20), ' ', LongWord(x + 20), ' ', Ord(Chr(Byte(x + 65))),
      ' ', Integer(x * 3), ' ', LongWord(x - $200000000));
  end;
  q := QWord($FFFFFFFFFFFFFFF0);
  writeln('q: ', LongWord(q + 32), ' ', Integer(q + 32), ' ', Ord(Boolean(LongWord(q + 16))),
    ' ', Ord(Boolean(LongWord(q + 17))));
  x := -5;
  writeln('neg: ', Integer(x * 1000000000), ' ', LongWord(x), ' ', Chr(Ord('A') + Integer(x + 30)));
end.
