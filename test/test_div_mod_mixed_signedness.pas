{ `div`/`mod` picked signed-vs-unsigned division from the DIVIDEND alone, so
  every unsigned-over-signed division ran unsigned and answered a huge positive
  number where FPC answers a small negative one:

    var w: Word = 40000; si: SmallInt = -25536;
    w div si     was 0        FPC: -1
    w mod si     was 40000    FPC: 14464

  Silent and value-wrong, at all four widths (Word/SmallInt, Byte/ShortInt,
  LongWord/Integer, QWord/Int64); every SIGNED dividend already agreed, and the
  explicitly-cast `Integer(w) div Integer(si)` was right, which is what makes it
  read as an operand-typing bug rather than a codegen one. Pascal widens the
  pair to a type that holds BOTH operands, so a signed divisor makes the whole
  division signed -- exactly the question TypeCompareUnsigned already answered
  for comparisons, and TypeDivideUnsigned now delegates to it instead of keeping
  a second, wronger rule.

  The unsigned cases below are the other half of the fix: an all-unsigned pair,
  and an unsigned dividend over a positive LITERAL (whose type is a wider signed
  int, so the wider-operand rule keeps `q div 10` unsigned) must NOT flip to
  signed -- that would turn every QWord above 2^63 negative.

  Every expectation is `fpc -O- -Mobjfpc` 3.2.2's.
  bug-p-div-of-an-unsigned-dividend-by-a-signed-divisor-divides-unsigned }
program test_div_mod_mixed_signedness;
{$mode objfpc}{$H+}

var
  ok, total: Integer;
  w: Word; si: SmallInt;
  b: Byte; sh: ShortInt;
  c: LongWord; i: Integer;
  q: QWord; n: Int64;
  u1, u2: LongWord;

procedure Chk(const what: string; got, want: Int64);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got ', got, ' want ', want);
end;

procedure ChkQ(const what: string; got, want: QWord);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got ', got, ' want ', want);
end;

procedure ChkB(const what: string; got, want: Boolean);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got ', got, ' want ', want);
end;

begin
  ok := 0; total := 0;

  { ---- unsigned dividend, SIGNED divisor: the bug. All four widths. ---- }
  w := 40000; si := -25536;
  Chk('w div si', w div si, -1);
  Chk('w mod si', w mod si, 14464);

  b := 200; sh := -3;
  Chk('b div sh', b div sh, -66);
  Chk('b mod sh', b mod sh, 2);

  c := 3000000000; i := -7;
  Chk('c div i', c div i, -428571428);
  Chk('c mod i', c mod i, 4);

  q := 18446744073709551615; n := -5;
  Chk('q div n', q div n, 0);
  Chk('q mod n', q mod n, -1);

  { the RESULT is a signed value, not a 2^64-sized positive one -- a comparison
    on it must see the sign (this is the node's own type, not just the bits) }
  ChkB('w div si is negative', (w div si) < 0, True);
  ChkB('c div i is negative', (c div i) < 0, True);

  { the same division through an explicit cast always worked; it must stay right }
  Chk('cast w div si', Integer(w) div Integer(si), -1);
  Chk('cast c div i', Int64(c) div i, -428571428);

  { ---- signed dividend, unsigned divisor: already agreed, must not move ---- }
  Chk('si div w', si div w, 0);
  Chk('si mod w', si mod w, -25536);
  Chk('sh div b', sh div b, 0);
  Chk('sh mod b', sh mod b, -3);
  Chk('i div c', i div c, 0);
  Chk('i mod c', i mod c, -7);

  { ---- all-unsigned pairs stay UNSIGNED (the half that was already right) ---- }
  u1 := 4000000000; u2 := 7;
  ChkQ('u1 div u2', u1 div u2, 571428571);
  ChkQ('u1 mod u2', u1 mod u2, 3);
  ChkB('u1 div u2 not negative', Int64(u1 div u2) < 0, False);

  q := 18446744073709551615;
  ChkQ('q div qword', q div QWord(3), 6148914691236517205);
  ChkQ('q mod qword', q mod QWord(3), 0);

  { an unsigned dividend over a POSITIVE LITERAL: the literal's type is wider
    and signed, and the wider operand decides -- so this stays unsigned, and a
    QWord above 2^63 does not go negative }
  ChkQ('q div 10', q div 10, 1844674407370955161);
  ChkQ('q mod 10', q mod 10, 5);
  ChkQ('c div 7', c div 7, 428571428);
  ChkQ('c mod 7', c mod 7, 4);
  Chk('w div 7', w div 7, 5714);
  Chk('w mod 7', w mod 7, 2);

  { mixed WIDTHS: the wider operand's signedness decides }
  ChkQ('q div c', q div c, 6148914691);
  Chk('c div si', c div si, -117481);
  Chk('w div i', w div i, -5714);

  { ---- signed/signed is untouched ---- }
  Chk('i div sh', i div sh, 2);
  Chk('n div i', n div i, 0);
  Chk('n mod i', n mod i, -5);

  writeln('total ok ', ok, ' / ', total);
end.
