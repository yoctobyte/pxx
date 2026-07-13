{ Small FPC-dialect gaps rtl-generics tripped over, batched (b329):

  1. `array[Byte] of X` — a SMALL ordinal type as the whole index range
     (Boolean/Char/enums worked, Byte/ShortInt/SmallInt/Word did not).
  2. PUInt8/PInt8/PUInt16/PInt16/PUInt32/PInt32 builtin pointer-type names
     (aliases of PByte/PShortInt/...).
  3. LOCAL var-section initializers: `var a: UInt32 = 1;` — FPC-legal, an
     assignment on every entry; was a hard error.
  4. Compound assignment STATEMENTS `a += e;` (-=, *=, /=) — FPC's
     {$COPERATORS}, always-on in the lax dialect; the expression parser and IR
     already owned the node (C frontend), only statement position was missing.
  Also (not testable here): {$I inc\file.inc} backslash include paths resolve
  on unix, and lib/rtl gained a minimal FPC-compat rtlconsts unit. }
program test_dialect_generics_prereqs_b329;
{$mode objfpc}{$h+}

var
  ByByte: array[Byte] of Integer;
  P: PUInt8;

function Adlerish(AKey: PUInt8; ALength: Integer): Cardinal;
var
  a: Cardinal = 1;
  b: Cardinal = 0;
  n: Integer;
begin
  for n := 0 to ALength - 1 do
  begin
    a := (a + AKey[n]) mod 65521;
    b := (b + a) mod 65521;
  end;
  Result := (b shl 16) or a;
end;

var
  buf: array[0..3] of Byte;
  i: Integer;
  acc: Integer;
begin
  Writeln('span=', High(ByByte) - Low(ByByte) + 1);
  for i := 0 to 3 do buf[i] := i + 1;
  P := @buf[0];
  Writeln('adler=', Adlerish(P, 4));
  acc := 10;
  acc += 5;
  acc -= 3;
  acc *= 4;
  Writeln('compound=', acc);
  Writeln('second-call a resets: ', Adlerish(P, 0));
end.
