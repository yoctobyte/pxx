program test_const_fold_overflows_into_qword;
{ A CONSTANT ADDITION THAT CARRIES INTO BIT 63 IS UNSIGNED, not a negative
  Int64. `high(int64)+100` is 9223372036854775907; it was typed tyInt64, so
  `if (high(int64)+100) > 0` took the NEGATIVE arm where fpc takes the positive
  one — a silent wrong branch on a constant written out in full.

  THE VALUE WAS ALWAYS RIGHT AND THE TYPE WAS WRONG, which is exactly why this
  survived: `q := high(int64)+100` has always stored fpc's exact bytes, so every
  store-and-print probe agrees and only a question that asks about the TYPE — a
  comparison, or an overload — reads back the signed view. The `stored` row
  below is here to be a row that PASSED BEFORE the fix; a fixture built only
  from stores would have been green throughout.

  The LITERAL half was already fixed at the literal's creation site, so the
  `lit` row also passed before. It stays as the control that says the FOLD is
  the gap: same value, two spellings, and only one of them was wrong.

  WHAT MUST NOT PROMOTE, and these are the rows that fail if the rule is too
  greedy: an ordinary small sum, a sum with a negative operand, and a fold that
  comes back DOWN out of the unsigned band. `-` needs no rule of its own —
  two non-negative operands cannot subtract into the sign bit, and a left
  operand already unsigned is carried by the QWord arm — so `+100-200` must
  stay positive and unsigned.

  `*` is deliberately not covered: a product can wrap PAST 2^64, where the
  value is representable in neither reading, so `lv*rv < 0` stops meaning
  "landed in the unsigned band". `high(int64)*2` is therefore still signed here
  and is NOT asserted — an assertion would freeze a behaviour nobody has argued
  for.

  .expected IS fpc 3.2.2's own output on this source, unmodified.
  bug-p-a-constant-expression-that-overflows-int64-stays-signed }
{$mode objfpc}

type
  TCei = record
    case signed: Boolean of
      False: (uvalue: qword);
      True:  (svalue: int64);
  end;

var
  chose: string;

operator := (const u: qword): TCei;
begin
  chose := 'qword';
  Result.signed := False; Result.uvalue := u;
end;

operator := (const s: int64): TCei;
begin
  chose := 'int64';
  Result.signed := True; Result.svalue := s;
end;

var
  q: qword;
  v: TCei;
begin
  q := high(int64) + 100;
  WriteLn('stored  = ', q);

  if (high(int64) + 100) > 0 then WriteLn('fold    = positive')
                             else WriteLn('fold    = negative');

  if 9223372036854775907 > 0 then WriteLn('lit     = positive')
                             else WriteLn('lit     = negative');

  { boundary: one past High(Int64) is already the unsigned band }
  if (high(int64) + 1) > 0 then WriteLn('plus1   = positive')
                           else WriteLn('plus1   = negative');

  { --- must NOT promote --- }
  if (2 + 3) > 0 then WriteLn('small   = positive') else WriteLn('small   = negative');
  if (high(int64) + 100 - 200) > 0 then WriteLn('backdown= positive')
                                   else WriteLn('backdown= negative');
  if (-1) > 0 then WriteLn('neglit  = positive') else WriteLn('neglit  = negative');
  if (1 + (-2)) > 0 then WriteLn('negsum  = positive') else WriteLn('negsum  = negative');

  { overload selection — the shape of fpc's own toperator6.pp, which halts(2)
    when the int64 operator is picked for the unsigned value }
  v := -128;
  WriteLn('ovl neg = ', chose);
  v := high(int64) + 100;
  WriteLn('ovl big = ', chose);
end.
