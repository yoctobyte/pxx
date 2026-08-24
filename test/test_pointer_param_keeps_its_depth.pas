program test_pointer_param_keeps_its_depth;
{ A pointer PARAMETER, a pointer CAPTURE, and `p^[i]` all keep the full pointer
  shape -- pointee, depth and ultimate base -- exactly as the identical GLOBAL
  does. Every line prints a character or a number that only comes out right if
  the callee still knows the argument was a `^PChar` (depth 2 over char) rather
  than a flattened PChar.

  Before the fix, Pascal's parameter table carried the pointee alone (C's has
  carried the depth and base all along), so `p^` inside the body yielded the raw
  address; the capture table lost it the same way one level further out; and
  `p^[i]` indexed the pointer VARIABLE by the pointer stride because the
  computed-pointer-value path in IRLowerAddress was gated on CProgramMode.
  All three shapes are pinned against fpc 3.2.2.
  feature-a-typeref-migrate-consumers }
type
  PPChar = ^PChar;
  PInt = ^Integer;
  PPInt = ^PInt;

var
  s: PChar;
  q: PPChar;
  i: Integer;
  pi: PInt;
  ppi: PPInt;

procedure ByValue(p: PPChar);
begin WriteLn('byvalue : ', p^); end;

procedure ByVar(var p: PPChar);
begin WriteLn('byvar   : ', p^); end;

procedure ByConst(const p: PPChar);
begin WriteLn('byconst : ', p^); end;

procedure IntPtr(p: PPInt);
begin WriteLn('intptr  : ', p^^); end;

procedure DerefIndex(p: PPChar);
begin WriteLn('paramidx: ', p^[1], p^[4]); end;

procedure Outer;
var
  loc: PPChar;

  procedure Inner;
  begin WriteLn('capture : ', loc^); end;

begin
  loc := q;
  Inner;
end;

begin
  s := 'hello';
  q := @s;
  i := 41;
  pi := @i;
  ppi := @pi;
  WriteLn('global  : ', q^);
  WriteLn('globalix: ', q^[1], q^[4]);
  ByValue(q);
  ByVar(q);
  ByConst(q);
  IntPtr(ppi);
  DerefIndex(q);
  Outer;
end.
