program test_strint_digits_and_width;
{ Str / write of an integer goes through StrInt (Int64) or StrQWord: digits
  into a stack buffer, a 64-bit loop until the value fits 31 (or 32) bits and
  a LongWord loop after, one allocation. Every boundary of that split, both
  ends of both types and the width padding are compared with literals. }
{$mode objfpc}
var bad: Integer;

procedure CheckI(v: Int64; w: Integer; const want: AnsiString);
var s: AnsiString;
begin
  Str(v:w, s);
  if s <> want then begin Inc(bad); writeln('BAD Str(', want, ':', w, ') = [', s, ']'); end;
end;

procedure CheckQ(v: QWord; w: Integer; const want: AnsiString);
var s: AnsiString;
begin
  Str(v:w, s);
  if s <> want then begin Inc(bad); writeln('BAD StrQ(', want, ':', w, ') = [', s, ']'); end;
end;

var s: AnsiString;
begin
  bad := 0;
  CheckI(0, 0, '0');
  CheckI(0, 3, '  0');
  CheckI(7, 1, '7');
  CheckI(-7, 0, '-7');
  CheckI(-7, 4, '  -7');
  CheckI(10, 0, '10');
  CheckI(-10, 0, '-10');
  CheckI(2147483647, 0, '2147483647');
  CheckI(2147483648, 0, '2147483648');
  CheckI(-2147483648, 0, '-2147483648');
  CheckI(-2147483649, 12, ' -2147483649');
  CheckI(4294967295, 0, '4294967295');
  CheckI(4294967296, 11, ' 4294967296');
  CheckI(1000000000000, 0, '1000000000000');
  CheckI(-999999999999, 0, '-999999999999');
  CheckI(High(Int64), 0, '9223372036854775807');
  CheckI(Low(Int64), 0, '-9223372036854775808');
  CheckI(Low(Int64), 25, '     -9223372036854775808');
  CheckI(123, 2, '123');
  CheckQ(0, 0, '0');
  CheckQ(4294967295, 0, '4294967295');
  CheckQ(4294967296, 0, '4294967296');
  CheckQ(QWord(1) shl 63, 0, '9223372036854775808');
  CheckQ(High(QWord), 22, '  18446744073709551615');
  s := '';
  Str(-42, s);
  writeln(s, ' ', bad = 0);
  writeln('bad=', bad);
end.
