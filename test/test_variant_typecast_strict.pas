program test_variant_typecast_strict;
{ --strict-fpc ONLY. FPC's Variant->Char rule: render the variant to its STRING
  form and take character 1. So Char(65) is '6' (not 'A'), Char(122) is '1',
  Char(2.5) is '2', Char(True) is 'T'.

  The DEFAULT dialect answers Chr(n) — see test_variant_typecast.pas. That
  deliberate divergence is why this file exists: the rule is inherited OLE
  history (FPC contradicts its own numeric Byte/Word/Int64 conversions of the
  same variant, and the string hop is unwritable by hand — `c := someAnsiString`
  is an FPC type error), so ordinary code gets the coherent answer and the
  conformance lane gets parity.

  Every value diffed against an FPC build of this file.
  bug-p-variant-to-int-and-char-conversion-diverges-from-fpc }
uses variants;
var v: Variant;
begin
  v := 65;    writeln(Char(v));   { 6  — character 1 of '65' }
  v := 7;     writeln(Char(v));   { 7 }
  v := 122;   writeln(Char(v));   { 1  — of '122', NOT 'z' }
  v := 2.5;   writeln(Char(v));   { 2  — of '2.5' }
  v := True;  writeln(Char(v));   { T  — of 'True' }
  v := 'hi';  writeln(Char(v));   { h }
  v := '';    writeln(Ord(Char(v)));   { 0 — empty string yields #0 }

  { the rows that track FPC in BOTH modes, so this file also proves the strict
    flag changes only the Char rule }
  v := 9;     writeln(Int64(v));  { 9 }
  v := True;  writeln(Int64(v));  { -1 }
  v := True;  writeln(Byte(v));   { 255 }
end.
