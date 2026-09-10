{ `bitsizeof(x)` -- an FPC intrinsic (compinnr.pas:85, in_bitsizeof_x) that
  FPC's own compiler uses throughout. It is SizeOf(x) * 8 and nothing else.

  THE ROWS ARE PAIRED ON PURPOSE. Each value row is followed by a row asserting
  the same answer equals SizeOf * 8, so the fixture pins the RELATION as well as
  the number. A per-target constant would have to be rewritten for every
  backend; the relation is true everywhere and still prints a different correct
  number on each. Both halves are needed: the relation alone passes if both
  sides are wrong together, and the constants alone say nothing about why.

  THE ONE INPUT WHERE FPC AND THE DESUGAR WOULD DIVERGE IS NOT REACHABLE:
  a `bitpacked` field, where fpc answers 2 for `a: 0..3`. pxx has no
  `bitpacked` -- `type T = bitpacked record` is `unknown type: bitpacked` --
  so there is no wrong answer available today, and the day that type lands
  this fixture is where the divergence shows up.
  umbrella-pxx-compiles-fpc-itself }
program test_p_bitsizeof_is_sizeof_times_eight;

type
  TSmallRec = record
    a: LongInt;
    b: LongInt;
  end;
  TArr = array[0..3] of LongInt;
  PLong = ^LongInt;

var
  fails: LongInt;
  li: LongInt;
  i64: Int64;
  by: Byte;
  ch: Char;
  wc: WideChar;
  rec: TSmallRec;
  arr: TArr;
  p: PLong;

procedure Chk(const what: AnsiString; got, want: LongInt);
begin
  if got = want then
    WriteLn(what, ' ok')
  else
  begin
    WriteLn(what, ' FAIL got=', got, ' want=', want);
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  li := 0; i64 := 0; by := 0; ch := 'a'; wc := 'a'; rec.a := 0; arr[0] := 0; p := nil;

  Chk('R01 var LongInt',    bitsizeof(li),    32);
  Chk('R02 rel LongInt',    bitsizeof(li),    SizeOf(li) * 8);
  Chk('R03 var Int64',      bitsizeof(i64),   64);
  Chk('R04 rel Int64',      bitsizeof(i64),   SizeOf(i64) * 8);
  Chk('R05 type LongInt',   bitsizeof(LongInt), 32);
  Chk('R06 rel type',       bitsizeof(LongInt), SizeOf(LongInt) * 8);
  Chk('R07 var Byte',       bitsizeof(by),    8);
  Chk('R08 rel Byte',       bitsizeof(by),    SizeOf(by) * 8);
  Chk('R09 type Byte',      bitsizeof(Byte),  8);
  Chk('R10 var Char',       bitsizeof(ch),    8);
  Chk('R11 rel Char',       bitsizeof(ch),    SizeOf(ch) * 8);
  Chk('R12 var WideChar',   bitsizeof(wc),    16);
  Chk('R13 rel WideChar',   bitsizeof(wc),    SizeOf(wc) * 8);
  Chk('R14 rel record',     bitsizeof(rec),   SizeOf(rec) * 8);
  Chk('R15 type record',    bitsizeof(TSmallRec), SizeOf(TSmallRec) * 8);
  Chk('R16 rel array',      bitsizeof(arr),   SizeOf(arr) * 8);
  Chk('R17 rel pointer',    bitsizeof(p),     SizeOf(p) * 8);
  Chk('R18 rel field',      bitsizeof(rec.a), SizeOf(rec.a) * 8);
  Chk('R19 rel elem',       bitsizeof(arr[0]), SizeOf(arr[0]) * 8);
  { ===== THE TWO NESTING ROWS, and only ONE of them discriminates =====
    A SizeOf inside a bitsizeof operand must not take the outer one's scale
    with it. R20 is the shape that looks like it tests that and DOES NOT: an
    index expression, measured 20 -> both answers 32, because whatever the
    scale is doing it is not reached through there.

    R21 is the one that does. `li + SizeOf(by)` is an EXPRESSION operand, so it
    parses through the factor chain and re-enters the SizeOf dispatch; with the
    scale held in shared state instead of a parameter the inner SizeOf resets
    it and this row answers 8. fpc 3.2.2 says 64 -- the expression promotes to
    Int64, which is also why it is a better row than a plain one: it pins the
    promotion and the re-entrancy at once. Both were checked by building the
    shared-state variant, not by reading the code.

    (`SizeOf(bitsizeof(li))` separates them too, at 4 against 32, and is
    deliberately NOT a row here: fpc answers 1, sizing an integer CONSTANT by
    its smallest fitting type, and that is the SizeOf-of-an-intermediate
    latitude CLAUDE.md settles as chosen rather than divergent. A fixture is
    the wrong place to freeze it.) }
  Chk('R20 nested, index',  bitsizeof(arr[SizeOf(by)]), 32);
  Chk('R21 nested, expr',   bitsizeof(li + SizeOf(by)), 64);

  WriteLn('fails=', fails);
  WriteLn('BITSIZEOF OK');
end.
