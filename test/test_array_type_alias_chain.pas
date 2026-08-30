program test_array_type_alias_chain;
{$MODE OBJFPC}{$H+}
{ bug-p-an-alias-to-a-named-dynamic-array-type-cannot-be-indexed

  `TB = TA` where TA is a NAMED array type used to file TB as a scalar of the
  ELEMENT kind, so SizeOf(y) was 4 rather than 8 and every array operation on y
  failed. SizeOf is the assertion that failed SILENTLY; the indexing errors were
  the loud symptom and would disappear first under a partial fix, so gating on
  them alone would let one through.

  The one-level lines are kept deliberately: the point of the finding is that
  one level always worked, so a regression that broke it would otherwise hide
  here. Static arrays and a third level are included because the fault was every
  array shape, not dynamic ones. }
type
  TA = array of Integer;
  TB = TA;                        { second level }
  TC = TB;                        { third level }
  TS = array[0..3] of Integer;
  TT = TS;                        { static, second level }
  TN = array of array of Integer;
  TM = TN;                        { array-of-array, second level }
var
  x: TA; y: TB; z: TC;
  s: TS; t: TT;
  n: TM;
begin
  { the silent assertion first }
  WriteLn('dyn   ', SizeOf(x), ' ', SizeOf(y), ' ', SizeOf(z));
  WriteLn('static ', SizeOf(s), ' ', SizeOf(t));
  { and that they actually behave as arrays }
  SetLength(x, 2); x[0] := 1; x[1] := 2;
  SetLength(y, 2); y[0] := 3; y[1] := 4;
  SetLength(z, 2); z[0] := 5; z[1] := 6;
  WriteLn('sums  ', x[0] + x[1], ' ', y[0] + y[1], ' ', z[0] + z[1]);
  WriteLn('len   ', Length(x), ' ', Length(y), ' ', Length(z));
  s[0] := 7; t[0] := 8;
  WriteLn('stat  ', s[0], ' ', t[0], ' ', Length(t));
  SetLength(n, 1);
  SetLength(n[0], 2);
  n[0][0] := 9; n[0][1] := 10;
  WriteLn('nested ', n[0][0] + n[0][1], ' ', Length(n));
end.
