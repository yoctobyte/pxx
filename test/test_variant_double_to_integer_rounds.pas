program test_variant_double_to_integer_rounds;
{ Converting a Variant that holds a Double to an integer ROUNDS half-to-even, as
  FPC's variant conversion table does. pxx truncated: `i := v` with v = 2.75
  answered 2, and -2.75 answered -2 -- a silent integer off by one, through every
  integer target, since Byte/Word/SmallInt/Integer/Int64 all narrow from the one
  helper (VariantToInt64).

  Two rows guard the scope of the rule:
    * `Trunc` on a plain Double variable is NOT affected -- it is not a variant
      conversion, and FPC keeps it truncating.
    * pxx's own Round() was already correct on every row here; only the variant
      path diverged. Asserted so a future "fix" to Round cannot hide behind this.

  Oracle: fpc 3.2.2 -Mobjfpc -O1 produces every value below. }
{$mode objfpc}{$H+}
uses variants;
var
  v: Variant;
  i: Integer;
  i6: Int64;
  by: Byte;
  wo: Word;
  sm: SmallInt;
  fails: Integer;

procedure Chk(const what: string; got, want: Int64);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

begin
  fails := 0;

  { --- half-to-even across the sign and both parities --- }
  v := 2.75;  i := v;  Chk('2.75',   i,  3);
  v := 2.5;   i := v;  Chk('2.5',    i,  2);
  v := 3.5;   i := v;  Chk('3.5',    i,  4);
  v := 1.5;   i := v;  Chk('1.5',    i,  2);
  v := 0.5;   i := v;  Chk('0.5',    i,  0);
  v := -2.5;  i := v;  Chk('-2.5',   i, -2);
  v := -2.75; i := v;  Chk('-2.75',  i, -3);
  v := 2.4;   i := v;  Chk('2.4',    i,  2);
  v := -2.4;  i := v;  Chk('-2.4',   i, -2);

  { --- every integer target narrows from the same helper --- }
  v := 2.75;
  i  := v;  Chk('Integer',  i,  3);
  i6 := v;  Chk('Int64',    i6, 3);
  by := v;  Chk('Byte',     by, 3);
  wo := v;  Chk('Word',     wo, 3);
  sm := v;  Chk('SmallInt', sm, 3);
  Chk('Integer() cast', Integer(v), 3);
  Chk('Int64() cast',   Int64(v),   3);

  { --- an integer-tagged variant is untouched --- }
  v := 7;   i := v;  Chk('int 7', i, 7);
  v := -7;  i := v;  Chk('int -7', i, -7);

  { --- scope: a plain Double is NOT a variant conversion --- }
  Chk('Trunc(2.75) plain', Trunc(2.75), 2);
  Chk('Trunc(-2.75) plain', Trunc(-2.75), -2);
  Chk('Round(2.75) plain', Round(2.75), 3);
  Chk('Round(2.5) plain',  Round(2.5),  2);
  Chk('Round(3.5) plain',  Round(3.5),  4);

  if fails = 0 then
    writeln('ALL OK')
  else
    writeln('FAILURES: ', fails);
end.
