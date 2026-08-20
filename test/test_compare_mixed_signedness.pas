{ A comparison picked its signed-vs-unsigned domain from the WIDER operand, a C
  rank rule. Pascal converts by RANGE -- the pair widens to a type that HOLDS
  BOTH -- so a signed operand narrower than an unsigned one still makes the
  comparison signed:

    var c: LongWord = 3000000000; si: SmallInt = -1;
    c > si     was FALSE    FPC: TRUE

  Under the old rule si sign-extended to $FFFF..FF and 3000000000 lost to it.
  The bug needed the widths to DIFFER, which is why the equal-width cases
  (`c > i`, `w > si`) were right all along and hid it.

  The exception is the one width where no wider signed type exists: an 8-byte
  unsigned operand against a NARROWER signed one converts the signed side to
  QWord, so `q > i` is FALSE -- but against Int64 it is signed again and `q > n`
  is TRUE. FPC 3.2.2 is the oracle for both, and it does not apply that
  carve-out to `div` (see test_div_mod_mixed_signedness): `q div i` is signed
  where `q > i` is unsigned. Every expectation below is `fpc -O- -Mobjfpc`'s.
  bug-p-div-of-an-unsigned-dividend-by-a-signed-divisor-divides-unsigned }
program test_compare_mixed_signedness;
{$mode objfpc}{$H+}

var
  ok, total: Integer;
  w: Word; si: SmallInt;
  b: Byte; sh: ShortInt;
  c: LongWord; i: Integer;
  q: QWord; n: Int64;
  c2: LongWord;

procedure Chk(const what: string; got, want: Boolean);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got ', got, ' want ', want);
end;

begin
  ok := 0; total := 0;
  w := 40000; si := -1; b := 200; sh := -1;
  c := 3000000000; i := -1; q := 9000000000000000000; n := -1;
  c2 := 7;

  { ---- unsigned WIDER than signed, and a wider signed type exists ---- }
  Chk('c > si', c > si, True);
  Chk('c < si', c < si, False);
  Chk('c > sh', c > sh, True);
  Chk('w > sh', w > sh, True);
  Chk('c >= si', c >= si, True);
  Chk('w <= sh', w <= sh, False);
  Chk('c <> si', c <> si, True);

  { ---- no wider signed type: 8-byte unsigned takes the pair unsigned... ---- }
  Chk('q > i', q > i, False);
  Chk('q > si', q > si, False);
  Chk('q > sh', q > sh, False);
  Chk('q < i', q < i, True);
  { ...except against Int64, where FPC compares signed }
  Chk('q > n', q > n, True);

  { ---- signed wider than unsigned: already right, must not move ---- }
  Chk('c > n', c > n, True);
  Chk('w > n', w > n, True);
  Chk('i > w', i > w, False);
  Chk('n > c', n > c, False);
  Chk('si > b', si > b, False);

  { ---- equal widths: signed wins, and always did ---- }
  Chk('c > i', c > i, True);
  Chk('w > si', w > si, True);
  Chk('b > sh', b > sh, True);

  { ---- both unsigned stays unsigned ---- }
  Chk('c > c2', c > c2, True);
  Chk('c2 > c', c2 > c, False);

  { ---- literals: a NON-NEGATIVE one is normalised to the unsigned domain, a
         negative one keeps the pair signed ---- }
  Chk('q > 10', q > 10, True);
  Chk('c > 10', c > 10, True);
  Chk('q > -1', q > -1, False);
  Chk('c > -1', c > -1, True);
  Chk('w > -1', w > -1, True);
  Chk('b > -1', b > -1, True);

  writeln('total ok ', ok, ' / ', total);
end.
