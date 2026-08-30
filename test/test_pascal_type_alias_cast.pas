program test_pascal_type_alias_cast;
{ bug-p-a-cast-through-an-ordinal-type-alias-does-not-truncate.

  A cast written with a BUILTIN type name narrowed; the identical cast written
  through a user-declared ALIAS of that same builtin did not — it fell into the
  pointer fall-through of the alias arm and reinterpreted at pointer width. With
  c = $12345678, `Byte(c)` gave 120 and `TaByte(c)` gave 305419896, and
  `TaChar(65)` segfaulted.

  Every expected value below is FPC 3.2.2's, taken from running this program
  under `fpc -Mobjfpc -Sh`, not from what pxx happened to print.

  THE LAST THREE ROWS PASSED THROUGHOUT and are the point of this test. The
  wrong value only escapes where the cast is consumed DIRECTLY — as an index, an
  argument, an operand. Assign it to a typed variable and the store truncates;
  mask it and the mask hides it. So the shapes a test is most naturally written
  in are exactly the shapes that pass, which is why a whole library indexed a
  [0..3, byte] table with ~4.3e9 and nothing anywhere reported it. A fix that
  handles only the direct case would keep them green; drop them and the test
  stops being able to tell a real fix from a partial one. }
{$mode objfpc}{$H+}
type
  TaByte = byte;  TaWord = word;  TaShort = shortint;  TaSmall = smallint;
  TaLW = longword; TaInt = integer; TaI64 = int64; TaQW = qword;
  TaChar = char; TaBool = boolean;
  TaAlias2 = TaByte;              { alias of an alias }
  TEnum = (eA, eB, eC); TaEnum = TEnum;
  PInt = ^Integer; TaPtr = PInt;  { a POINTER alias must stay a reinterpret }
  TaD = double; TaS = single;     { float aliases CONVERT, they do not reinterpret }
var c: cardinal; i64: int64; p: PInt; n: Integer; b: byte;
begin
  c := $12345678; i64 := $123456789A;
  WriteLn('TaByte  ', TaByte(c));      { 120 }
  WriteLn('TaWord  ', TaWord(c));      { 22136 }
  WriteLn('TaShort ', TaShort(c));     { 120 }
  WriteLn('TaSmall ', TaSmall(c));     { 22136 }
  WriteLn('TaLW    ', TaLW(i64));      { 878082202 }
  WriteLn('TaInt   ', TaInt(i64));     { 878082202 }
  WriteLn('TaI64   ', TaI64(c));       { 305419896 — no narrowing needed }
  WriteLn('TaQW    ', TaQW(c));        { 305419896 }
  WriteLn('TaAlias2 ', TaAlias2(c));   { 120 — an alias of an alias narrows too }
  WriteLn('TaChar  ', TaChar(65));     { A — this one used to SEGFAULT }
  WriteLn('TaBool  ', TaBool(1));      { TRUE }
  WriteLn('TaEnum  ', Ord(TaEnum(2))); { 2 — enum identity survives the cast }
  n := 7; p := @n;
  WriteLn('TaPtr   ', TaPtr(p)^);      { 7 — pointer aliases unchanged }
  WriteLn('TaD     ', TaD(3.75):0:2);  { 3.75 — not the IEEE bit pattern }
  WriteLn('TaS     ', TaS(1.5):0:2);   { 1.50 }
  { the three that always passed — see the header }
  b := TaByte(c);
  WriteLn('assigned ', b);             { 120: the STORE truncates }
  WriteLn('masked   ', TaByte(c) and 255);  { 120: the MASK hides it }
  WriteLn('ord      ', Ord(TaByte(c)));     { 120 }
end.
