{ `Str(x, s)` had no unsigned dispatch at all, so an 8-byte unsigned value came
  out as a small negative number:

    var q: QWord; s: string;
    q := 18446744073709551615;
    Str(q, s);        s was '-1'        FPC: '18446744073709551615'
    writeln(q);       printed it right  <- two lines apart, two answers

  `write(Text)` had the dispatch but keyed it on `tk = tyUInt64`, one of the
  FOUR spellings of an 8-byte unsigned, so `writeln(f, pu)` with `pu: PtrUInt`
  (tyNativeUInt) printed -1 as well. Only the stdout path, which keys on plain
  `not TypeSigned`, was right -- and that is the rule all three now use.

  Every expectation is `fpc -O- -Mobjfpc` 3.2.2's.
  bug-p-str-of-a-qword-formats-it-signed }
program test_str_of_unsigned;
{$mode objfpc}{$H+}

var
  ok, total: Integer;
  q: QWord; c: LongWord; w: Word; b: Byte;
  n: Int64; i: Integer; si: SmallInt; sh: ShortInt;
  pu: PtrUInt; nv: NativeUInt; ni: NativeInt;
  s: string; f: text;

procedure Chk(const what, got, want: string);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got [', got, '] want [', want, ']');
end;

begin
  ok := 0; total := 0;
  q := 18446744073709551615; c := 4294967295; w := 65535; b := 255;
  n := -1; i := -1; si := -1; sh := -1;
  pu := PtrUInt(q); nv := NativeUInt(q); ni := -1;

  { ---- the four 8-byte unsigned spellings ---- }
  Str(q, s);  Chk('Str QWord', s, '18446744073709551615');
  Str(pu, s); Chk('Str PtrUInt', s, '18446744073709551615');
  Str(nv, s); Chk('Str NativeUInt', s, '18446744073709551615');
  q := 9223372036854775808;
  Str(q, s);  Chk('Str 2^63', s, '9223372036854775808');
  q := 18446744073709551615;

  { ---- narrower unsigned: was already right, must stay ---- }
  Str(c, s);  Chk('Str LongWord', s, '4294967295');
  Str(w, s);  Chk('Str Word', s, '65535');
  Str(b, s);  Chk('Str Byte', s, '255');

  { ---- signed: must NOT take the unsigned formatter ---- }
  Str(n, s);  Chk('Str Int64', s, '-1');
  Str(i, s);  Chk('Str Integer', s, '-1');
  Str(si, s); Chk('Str SmallInt', s, '-1');
  Str(sh, s); Chk('Str ShortInt', s, '-1');
  Str(ni, s); Chk('Str NativeInt', s, '-1');

  { ---- widths, on both sides of the dispatch ---- }
  Str(q:25, s); Chk('Str QWord:25', s, '     18446744073709551615');
  Str(b:6, s);  Chk('Str Byte:6', s, '   255');
  Str(i:6, s);  Chk('Str Integer:6', s, '    -1');

  { ---- an EXPRESSION, not just a variable ---- }
  Str(c * 2, s);  Chk('Str c*2', s, '8589934590');
  Str(b + 1, s);  Chk('Str b+1', s, '256');
  Str(q div 10, s); Chk('Str q div 10', s, '1844674407370955161');

  { ---- the same dispatch through a TEXT file ---- }
  Assign(f, 'test_str_unsigned.out'); Rewrite(f);
  writeln(f, q); writeln(f, pu); writeln(f, b); writeln(f, n); writeln(f, w:8);
  Close(f);
  Assign(f, 'test_str_unsigned.out'); Reset(f);
  readln(f, s); Chk('write(f) QWord', s, '18446744073709551615');
  readln(f, s); Chk('write(f) PtrUInt', s, '18446744073709551615');
  readln(f, s); Chk('write(f) Byte', s, '255');
  readln(f, s); Chk('write(f) Int64', s, '-1');
  readln(f, s); Chk('write(f) Word:8', s, '   65535');
  Close(f);
  Erase(f);

  writeln('total ok ', ok, ' / ', total);
end.
