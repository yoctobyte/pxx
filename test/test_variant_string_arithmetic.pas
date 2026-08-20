{ Arithmetic on a Variant holding a STRING read the payload as a number instead
  of converting it:

    v := '15'; w := 3;
    v - w      was 139332782393069   FPC: 12    <- the AnsiString HANDLE
    v * w      was 417998347179216   FPC: 45    <- the same address, x3

  A one-character string answered its CHAR ORDINAL instead (`'5' - 3` was 50,
  Ord('5') - 3), and `+` took the concat branch whenever EITHER side was
  stringy while rendering only the stringy one, so `'5' + 3` was '5' and
  `5 + '3'` was '3'. Fourteen wrong rows, none of them announced, and the
  multi-character ones printed a different number every run.

  Pascal converts a stringy operand to a NUMBER for arithmetic -- FPC's rule,
  which pxx already implemented in VariantToInt64 for `i := v` and simply never
  called from the binop path. Concatenation is now what it is in FPC: `+` with
  BOTH operands stringy. NilPy keeps Python's rules ('5' * 3 is '555', '5' + 3
  is a TypeError); it is excluded at emit time, not at run time.

  Every expectation is `fpc -O- -Mobjfpc` 3.2.2's.
  bug-p-variant-arithmetic-on-a-string-reads-the-payload-as-a-number }
program test_variant_string_arithmetic;
{$mode objfpc}{$H+}
uses variants, sysutils;

var
  ok, total: Integer;
  v, w: Variant;

procedure Chk(const what, got, want: string);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got [', got, '] want [', want, ']');
end;

begin
  ok := 0; total := 0;

  { ---- a ONE-character numeric string: was the char ordinal ---- }
  v := '5'; w := 3;
  Chk('c+i', v + w, '8');
  Chk('c-i', v - w, '2');
  Chk('c*i', v * w, '15');

  { ---- a MULTI-character one: was the AnsiString handle ---- }
  v := '15'; w := 3;
  Chk('s+i', v + w, '18');
  Chk('s-i', v - w, '12');
  Chk('s*i', v * w, '45');

  { ---- the string on the RIGHT ---- }
  v := 3; w := '5';
  Chk('i+s', v + w, '8');
  Chk('i-s', v - w, '-2');
  Chk('i*s', v * w, '15');

  { ---- a DOUBLE on the other side: the pair must promote, not truncate ---- }
  v := '5'; w := 2.5;
  Chk('s+d', v + w, '7.5');
  Chk('s-d', v - w, '2.5');
  Chk('s*d', v * w, '12.5');

  { ---- a FRACTIONAL string coerces to a double, not to 0 ---- }
  v := '2.5'; w := 3;
  Chk('frac*i', v * w, '7.5');
  Chk('frac+i', v + w, '5.5');

  { ---- a negative string ---- }
  v := '-5'; w := 2;
  Chk('neg div', v / w, '-2.5');
  Chk('neg*i', v * w, '-10');

  { ---- BOTH stringy: `+` still CONCATENATES, and only then ---- }
  v := '5'; w := '3';
  Chk('s+s concat', v + w, '53');
  Chk('s-s', v - w, '2');
  Chk('s*s', v * w, '15');
  v := 'x'; w := 'y';
  Chk('c+c concat', v + w, 'xy');

  { ---- no stringy operand: untouched ---- }
  v := 7; w := 2;
  Chk('i+i', v + w, '9');
  Chk('i-i', v - w, '5');
  Chk('i*i', v * w, '14');
  v := 7.5; w := 3;
  Chk('d*i', v * w, '22.5');

  { ---- comparisons are NOT part of this fix: a mixed string/number pair
         compares unequal and unordered here, where FPC converts (so `3 < '5'`
         is TRUE in FPC and FALSE here). Asserted as it IS, so the day it
         changes this test says so. ---- }
  v := '5'; w := 3;
  Chk('c=i', BoolToStr(v = w, True), 'False');
  Chk('c<i', BoolToStr(v < w, True), 'False');
  v := 'x'; w := 'y';
  Chk('c<c', BoolToStr(v < w, True), 'True');

  writeln('total ok ', ok, ' / ', total);
end.
