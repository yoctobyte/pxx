{ `Integer(x)` in RVALUE position did not truncate to 32 bits — it handed the
  operand's bit pattern straight through:

    var c: LongWord;  c := 4000000000;
    Writeln(Integer(c));    was 4000000000    FPC: -294967296

  and yet `LongInt(c)`, the exact same cast spelled the other way, was right,
  because `longint` is not a type TOKEN (only `byte`, `integer` and `longword`
  are) and so took the identifier path into a real truncating AN_PTR_CAST.
  Assigning to an Integer variable was right too, because the 4-byte store
  truncates for free. So one concept had two spellings and three contexts, and
  exactly one combination was wrong — which is why it survived.

  bug-narrowing-typecast-rvalue-no-truncate fixed byte/word/cardinal/longword/
  shortint here in 2026-07 and said of this arm "integer/longint keep their
  exact existing passthrough behavior, zero regression risk there". That is the
  arm this test now pins.

  Every expectation is `fpc -O- -Mobjfpc`'s.
  bug-p-integer-cast-does-not-truncate-in-rvalue-position }
program test_integer_cast_truncates_rvalue;
{$mode objfpc}{$H+}

var
  ok, total: Integer;
  c: LongWord; n: Int64; q: QWord; i: Integer; w: Word; b: Byte;
  si: SmallInt; sh: ShortInt;

procedure Chk(const what: string; got, want: Int64);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got ', got, ' want ', want);
end;

begin
  ok := 0; total := 0;

  { the case that was wrong: a 32-bit UNSIGNED operand reinterpreted as signed }
  c := 4000000000;
  Chk('rvalue', Integer(c), -294967296);
  Chk('synonym', LongInt(c), -294967296);
  i := Integer(c);
  Chk('assigned', i, -294967296);          { always worked — the store truncated }
  Chk('folded', Integer(LongWord(4000000000)), -294967296);
  Chk('in expr', Integer(c) + 1, -294967295);
  Chk('compared', Ord(Integer(c) < 0), 1);
  c := $FFFFFFFF;  Chk('allones', Integer(c), -1);
  c := $80000000;  Chk('signbit', Integer(c), -2147483648);
  c := $7FFFFFFF;  Chk('maxpos', Integer(c), 2147483647);
  c := 0;          Chk('zero', Integer(c), 0);

  { a WIDER operand truncates to its low 32 bits }
  n := 9223372036854775807;  Chk('i64max', Integer(n), -1);
  n := $100000000;         Chk('bit32', Integer(n), 0);
  n := $10000002A;         Chk('bit32+42', Integer(n), 42);
  n := -1;                   Chk('i64m1', Integer(n), -1);
  q := 18446744073709551615; Chk('qmax', Integer(q), -1);

  { an operand that cannot change value keeps the pun — asserted so the guard
    that keeps `Integer(someInteger)` free of masking stays honest }
  i := -1;      Chk('int', Integer(i), -1);
  i := 300;     Chk('int300', Integer(i), 300);
  w := 40000;   Chk('word', Integer(w), 40000);
  b := 200;     Chk('byte', Integer(b), 200);
  si := -30000; Chk('smallint', Integer(si), -30000);
  sh := -100;   Chk('shortint', Integer(sh), -100);
  Chk('char', Integer('A'), 65);
  Chk('bool', Integer(True), 1);

  { the neighbours that bug-narrowing-typecast-rvalue-no-truncate already fixed,
    re-asserted so this change cannot disturb them }
  i := 300;  Chk('nb byte', Byte(i), 44);
  i := 70000; Chk('nb word', Word(i), 4464);
  i := -1;   Chk('nb cardinal', Cardinal(i), 4294967295);
  Chk('nb longword', LongWord(i), 4294967295);
  i := 200;  Chk('nb shortint', ShortInt(i), -56);

  writeln('total ok ', ok, ' / ', total);
end.
