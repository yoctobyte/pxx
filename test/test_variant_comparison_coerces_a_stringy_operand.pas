program test_variant_comparison_coerces_a_stringy_operand;
{ A Variant comparison with ONE stringy operand converts the text and compares
  numerically, exactly as FPC does. `v(1) = v('1')` used to answer FALSE -- a
  silent wrong boolean, and the safe-looking one, so a filter over variants that
  arrived from text (a config value, a parsed field) simply matched nothing.

  The rule has three cases and only the middle one changed:
    both stringy    -> string comparison        ('ab' < 'ac')
    exactly one     -> convert the text, compare numerically
    neither         -> numeric comparison, as before

  Arithmetic is asserted alongside it because the fix moved where the shared
  coercion is emitted, and `'5' + '3'` must still concatenate.

  The rule lives in TWO implementations -- EmitVarBinOp (x86-64, inline) and
  PXXVarBinOpPas (i386/arm32/aarch64/riscv32) -- which have drifted apart once
  before. This test is the thing that notices next time.

  Oracle: fpc 3.2.2 -Mobjfpc -O1 produces every value below. }
{$mode objfpc}{$H+}
var
  a, b, c: Variant;
  fails: Integer;

procedure ChkB(const what: string; got, want: Boolean);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

procedure ChkS(const what: string; got: Variant; const want: string);
begin
  if string(got) <> want then
  begin
    writeln('FAIL ', what, ': got "', string(got), '" want "', want, '"');
    Inc(fails);
  end;
end;

begin
  fails := 0;

  { --- exactly one stringy: convert and compare numerically --- }
  a := 1;    b := '1';   ChkB('int=str',      a = b,  True);
  a := 1;    b := '1';   ChkB('int<>str',     a <> b, False);
  a := '1';  b := 1;     ChkB('str=int',      a = b,  True);
  a := 1;    b := '2';   ChkB('int<str',      a < b,  True);
  a := 1;    b := '2';   ChkB('int<=str',     a <= b, True);
  a := 1;    b := '2';   ChkB('int>str',      a > b,  False);
  a := 1;    b := '2';   ChkB('int>=str',     a >= b, False);
  a := 2;    b := '1';   ChkB('int>str2',     a > b,  True);
  a := '10'; b := 9;     ChkB('str>int num',  a > b,  True);   { 10 > 9, not '10' < '9' }
  a := 1.5;  b := '1.5'; ChkB('dbl=str',      a = b,  True);
  a := 2.5;  b := '2.5'; ChkB('dbl=str2',     a = b,  True);

  { --- both stringy: a real string comparison, NOT a numeric one --- }
  a := 'ab'; b := 'ab';  ChkB('str=str',      a = b,  True);
  a := 'ab'; b := 'ac';  ChkB('str<str',      a < b,  True);
  a := 'ab'; b := 'ac';  ChkB('str>str',      a > b,  False);
  a := '1';  b := '1.0'; ChkB('str="1.0"',    a = b,  False);  { text, so unequal }
  a := 'x';  b := 'x';   ChkB('char=char',    a = b,  True);

  { --- neither stringy: unchanged --- }
  a := 2;    b := 2;     ChkB('int=int',      a = b,  True);
  a := 2;    b := 2;     ChkB('int<int',      a < b,  False);
  a := 2.5;  b := 2.5;   ChkB('dbl=dbl',      a = b,  True);
  a := 1;    b := 1.0;   ChkB('int=dbl',      a = b,  True);
  a := True; b := True;  ChkB('bool=bool',    a = b,  True);

  { --- arithmetic, unchanged by the coercion move --- }
  a := '5';  b := '3';   c := a + b;  ChkS('cat',   c, '53');
  a := '5';  b := 3;     c := a + b;  ChkS('str+i', c, '8');
  a := 5;    b := '3';   c := a + b;  ChkS('i+str', c, '8');
  a := '15'; b := 3;     c := a - b;  ChkS('str-i', c, '12');
  a := '5';  b := 2.5;   c := a + b;  ChkS('str+d', c, '7.5');
  a := '6';  b := '3';   c := a - b;  ChkS('str-str', c, '3');
  a := '6';  b := '3';   c := a * b;  ChkS('str*str', c, '18');

  if fails = 0 then
    writeln('ALL OK')
  else
    writeln('FAILURES: ', fails);
end.
