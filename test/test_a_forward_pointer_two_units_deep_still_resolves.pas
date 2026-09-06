{ A forward `^T` in a unit the program reaches only TRANSITIVELY.

  The unresolved-`^T` refusal shipped once draining ONCE, at the program's final
  `end.` (393fe0184), and was reverted the same day (d11b8a1a9): that asks the
  name question from the PROGRAM's scope, and a type declared in a unit reached
  only through another unit is not visible there. `uses syncobjs` stopped
  compiling for the whole fleet over palsync's `PMutex = ^TMutex;` sitting four
  lines above its own record -- while `uses palsync` DIRECTLY still worked, which
  is why the first three attempts to reduce it all produced the working case.

  ONE `uses` LEVEL IS NOT THE TEST. ufpmid exists for no other reason than to be
  the second level; delete it, point the program at ufpdeep, and this file passes
  against the broken compiler. That is the whole content of the regression.

  The direct row is kept beside it as the control, so a future change that breaks
  the ONE-level case cannot hide behind the two-level one passing. }
program test_a_forward_pointer_two_units_deep_still_resolves;
{$mode objfpc}

uses ufpmid, ufpdeep;

var
  x: TX;
  p: PX;

begin
  { two levels: the program never names ufpdeep's types, ufpmid does }
  writeln('deep   ', Deep);
  { one level: the control }
  FillIt(x);
  p := @x;
  writeln('direct ', p^.v + 1);
end.
