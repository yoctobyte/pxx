program test_writeln_of_an_enum_prints_its_name;
{ `WriteLn(e)` over an enum prints the member NAME, as FPC does. It printed the
  ORDINAL — 1 where FPC prints `Two` — silently, exit 0.

  A Boolean is an enum with two members, and this compiler already knew to print
  TRUE/FALSE for one: the same concept reached through two shapes, with the
  answer on only the two-member shape (normalise-dont-special-case). The lowering
  is now IRLowerBoolWrite's twin with N arms.

  Covers: a plain variable, a member literal, explicit ordinals (`= 5`), a
  scoped-looking single-member type, the field-width form (FPC LEFT-aligns an
  enum where it right-aligns a string and a boolean — the third line asserts all
  three on one row), Write vs WriteLn, and Ord() still answering the number.

  Every OTHER way of naming the same value — an array element, a record or class
  field, a call result, a param, a typed const, a cast, Succ/Pred — lives in its
  twin, test_enum_name_through_field_index_and_call.pas. It printed the ordinal
  here until the identity was threaded through each of those shapes.

  .expected IS fpc 3.2.2's own output on this source. }
{$mode objfpc}
type
  TColour = (clRed, clGreen, clBlue);
  THoles  = (hLow = 5, hMid = 9, hHigh = 40);
  TOne    = (oOnly);

var
  c: TColour; h: THoles; o: TOne; b: Boolean; s: string;

begin
  c := clGreen;
  WriteLn('var    : ', c);
  c := clRed;   Write('lit    : ', c, ' ');
  c := clBlue;  WriteLn(c);

  h := hLow;  WriteLn('holes  : ', h);
  h := hMid;  WriteLn('holes  : ', h);
  h := hHigh; WriteLn('holes  : ', h);

  o := oOnly; WriteLn('one    : ', o);

  { alignment: enum LEFT, boolean and string RIGHT — all three in one row }
  c := clBlue; b := True; s := 'abc';
  WriteLn('width  : [', c:8, '][', b:8, '][', s:8, ']');
  c := clRed;
  WriteLn('width  : [', c:8, '][', c:2, ']');

  { Ord still answers the ordinal, and so does an explicit integer context }
  c := clBlue; h := hMid;
  WriteLn('ord    : ', Ord(c), ' ', Ord(h));
  WriteLn('cmp    : ', c > clRed, ' ', h = hMid);
end.
