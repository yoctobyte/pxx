{ SPDX-License-Identifier: MPL-2.0 }
program test_val_float_correctly_rounded;
{ Val(s, d, code) on a Double must land on the NEAREST double, compared on the
  bits. Input lines are `repr(d) HEXBITS` from
  test_val_float_correctly_rounded_gen.py (CPython as the oracle). Before the
  fix Val rounded once per digit and once per decade of exponent and missed
  1574 of 6000; StrToFloat, a different parser, missed none. Val now takes its
  value from the same parser (lib/rtl/decfloat.pas).
  bug-b-val-of-a-float-is-not-correctly-rounded-while-strtofloat-of-the-same-string-is

  Only builtin is used -- no sysutils -- so this measures Val alone. }

function Hex16(q: QWord): AnsiString;
const digits = '0123456789ABCDEF';
var i: Integer;
begin
  SetLength(Result, 16);
  for i := 16 downto 1 do
  begin
    Result[i] := digits[Integer(q and 15) + 1];
    q := q shr 4;
  end;
end;

var
  line, num, want, got: AnsiString;
  d: Double;
  code, sp, total, bad: Integer;
begin
  total := 0;
  bad := 0;
  while not EOF do
  begin
    ReadLn(line);
    if line = '' then Continue;
    sp := Pos(' ', line);
    num := Copy(line, 1, sp - 1);
    want := Copy(line, sp + 1, Length(line) - sp);
    Val(num, d, code);
    got := Hex16(PQWord(@d)^);
    total := total + 1;
    if (code <> 0) or (got <> want) then
    begin
      bad := bad + 1;
      if bad <= 5 then
        WriteLn('MISS ', num, ' code=', code, ' got ', got, ' want ', want);
    end;
  end;
  WriteLn('val-float: ', total - bad, ' / ', total, ' exact');
end.
