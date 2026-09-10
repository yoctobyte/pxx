{ CompareByte returns the signed DIFFERENCE of the first differing elements,
  NOT a sign. Measured against fpc 3.2.2: 20 against 25 is -5 and 25 against
  20 is +5.

  This is the row that had to be measured rather than implemented from the
  name. Every caller that writes `if CompareByte(a, b, n) < 0` passes under
  either reading, so a <0/0/>0 implementation looks correct indefinitely and
  breaks only a caller that uses the magnitude -- and FPC's own compiler
  sources call CompareByte 16 times. Control, measured both compilers: a
  sign-returning implementation of the same routine answers -1 and +1 here
  where these rows want -5 and +5, so R02 and R03 do discriminate.

  CompareByte was already in the builtin auto-include scan when the rest of
  its family was not, which is why it is tested apart from them -- naming it
  in the family file pulled the builtin unit in and hid that six siblings
  were unreachable. See test_p_index_and_compare_family.pas.
  umbrella-pxx-compiles-fpc-itself }
program test_p_comparebyte_returns_the_signed_difference;

var
  fails: LongInt;
  b, b2: array[0..5] of Byte;

procedure Chk(const what: AnsiString; got, want: Int64);
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
  b[0]:=10;  b[1]:=20; b[2]:=30; b[3]:=20; b[4]:=40; b[5]:=50;
  b2[0]:=10; b2[1]:=25; b2[2]:=30; b2[3]:=20; b2[4]:=40; b2[5]:=50;

  Chk('R01 eq',    CompareByte(b, b, 6), 0);
  Chk('R02 lt',    CompareByte(b, b2, 6), -5);
  Chk('R03 gt',    CompareByte(b2, b, 6), 5);
  { len stops the scan BEFORE the differing element at index 1 }
  Chk('R04 len0',  CompareByte(b, b2, 0), 0);
  Chk('R05 pre',   CompareByte(b, b2, 1), 0);

  WriteLn('fails=', fails);
  WriteLn('CMPBYTE OK');
end.
