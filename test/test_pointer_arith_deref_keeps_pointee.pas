{ `(p + k)^` resolved its pointee type only when the inner node was a bare
  identifier or `arr[i]`; a BINOP "carries no element-type tag" and defaulted to
  Integer. That default is correct for a `^Integer` and wrong for every other
  pointer:

    pc: PChar;  (pc + 2)^   was 1717920867   FPC: 'c'

  1717920867 is $66656463 -- the four bytes `dcef` read as an integer. The
  address was right and the memory was right; the SPAN was four bytes instead of
  one. `pc^` and `pc[2]`, the two other spellings of the same access, were both
  correct all along, so the three spellings of one concept disagreed and only
  the arithmetic one was wrong.

  On a ^Byte and a ^SmallInt it reads past the element the same way; on a
  ^Int64 it reads SHORT, which is why `(q64 + 0)^ = q64^` was False. Every
  expectation is `fpc -O- -Mobjfpc`'s.
  bug-p-a-pchar-plus-offset-loses-its-type-when-dereferenced }
program test_pointer_arith_deref_keeps_pointee;
{$mode objfpc}{$H+}

type
  QB = ^Byte; QI = ^Integer; QI64 = ^Int64; QS = ^SmallInt;

var
  cb: array[0..15] of Byte;
  ci: array[0..7] of Integer;
  ca: array[0..7] of Char;
  xb: QB; xi: QI; pc: PChar; xs: QS; x64: QI64;
  ok, total, k: Integer;

procedure Chk(const what: string; got, want: Int64);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got ', got, ' want ', want);
end;

begin
  ok := 0; total := 0;
  for k := 0 to 15 do cb[k] := k + 1;
  for k := 0 to 7 do ci[k] := 100 + k;
  for k := 0 to 7 do ca[k] := Chr(97 + k);

  { ^Byte -- one byte, not four }
  xb := @cb[0];
  Chk('byte deref', xb^, 1);
  Chk('byte +3', (xb + 3)^, 4);
  Chk('byte idx', xb[3], 4);
  Chk('byte +0', (xb + 0)^, 1);

  { ^Integer -- the one the old default happened to get right }
  xi := @ci[0];
  Chk('int deref', xi^, 100);
  Chk('int +2', (xi + 2)^, 102);
  Chk('int nested', ((xi + 1) + 1)^, 102);
  Chk('int minus', (xi + 3 - 1)^, 102);

  { PChar -- the reported case }
  pc := @ca[0];
  Chk('char deref', Ord(pc^), 97);
  Chk('char +2', Ord((pc + 2)^), 99);
  Chk('char idx', Ord(pc[2]), 99);

  { ^SmallInt -- two bytes; 513 = $0201 from bytes 1,2 }
  xs := @cb[0];
  Chk('small deref', xs^, 513);
  Chk('small +1', (xs + 1)^, 1027);

  { ^Int64 -- eight bytes; the old default read only four }
  x64 := @cb[0];
  Chk('i64 agrees', Ord((x64 + 0)^ = x64^), 1);
  Chk('i64 value', (x64 + 0)^, x64^);

  { a plain parenthesised pointer keeps working }
  Chk('paren byte', (xb)^, 1);
  Chk('paren char', Ord((pc)^), 97);

  writeln('total ok ', ok, ' / ', total);
end.
