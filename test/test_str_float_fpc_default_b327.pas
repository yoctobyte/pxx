{ `Str(F, S)` with no width uses FPC's default scientific form (b327).

  FPC's Str(Double) with no width yields ` d.ddddddddddddddddE+eee` — 17
  significant digits, a LEADING SPACE where the '-' would go, 3-digit signed
  exponent. Ours produced compact '1.2', so fcl-json's float tests — which do
  `Str(F,S); Delete(S,1,1)` and compare with the DOM's Str-based output —
  diverged char 1. Explicit width/decimals forms are unchanged, as is
  writeln's float formatting. Verified against FPC (last-ULP digits of the
  17-digit mantissa may differ from FPC's exact converter on some values;
  the cases below are exact). }
program test_str_float_fpc_default_b327;
{$mode objfpc}{$h+}

var
  S: String;
  F: Double;
begin
  F := 1.2;    Str(F, S); Writeln('[', S, ']');
  F := 0;      Str(F, S); Writeln('[', S, ']');
  F := -1.5;   Str(F, S); Writeln('[', S, ']');
  F := 1.2;    Str(F:8:3, S); Writeln('[', S, ']');   { explicit form unchanged }
  Writeln(1.2:0:2);                                    { writeln unchanged }
end.
