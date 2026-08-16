{ `Integer` and `LongInt` are the same 4-byte signed type, but carried distinct
  TypeKinds, so the exact-match phase of overload resolution discriminated on
  the SPELLING (bug-p-integer-and-longint-are-not-the-same-type-in-overload-
  matching). sysutils declares IntToHex for Int64/LongInt/LongWord exactly so a
  32-bit value renders 8 digits: `longint` got that, `integer` bound Int64 and
  rendered 16. Values below are `fpc -O- -Mobjfpc`'s. }
program test_integer_longint_overload;
{$mode objfpc}{$H+}
uses sysutils;

function Which(x: longint): string; overload; begin Which := 'longint'; end;
function Which(x: int64): string; overload; begin Which := 'int64'; end;
function Which(x: longword): string; overload; begin Which := 'longword'; end;

var i: integer; li: longint; i64: int64; c: cardinal;
begin
  i := -1; li := -1; i64 := -1; c := 4294967295;
  writeln(IntToHex(i, 8), ' ', IntToHex(li, 8), ' ', IntToHex(c, 8));
  writeln(IntToHex(i64, 8), ' ', IntToHex(-1, 8));
  writeln(Which(i), ' ', Which(li), ' ', Which(i64), ' ', Which(c));
end.
