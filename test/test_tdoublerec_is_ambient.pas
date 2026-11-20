{ FPC names TDoubleRec/TSingleRec/TFloatSpecial with no `uses` (System, mathh.inc);
  pxx loads lib/rtl/floatrec.pas when a program names one. Output = fpc 3.2.2
  except BuildUp(True, 0, 3): fpc prints 8.0 (its double BuildUp drops the
  sign; its single one keeps it), the IEEE bits say -8.0.
  feature-b-rtl-has-no-tdoublerec }
program test_tdoublerec_is_ambient;
{$mode objfpc}
var r: TDoubleRec; s: TSingleRec; d: Double;
begin
  r.Value := 1.5;
  writeln(SizeOf(r), ' ', SizeOf(s), ' ', r.Sign, ' ', r.Exp, ' ', r.Frac, ' ', r.Exponent, ' ', r.Mantissa(True));
  writeln(r.Data, ' ', r.Bytes[7], ' ', r.Words[3]);
  r.Value := -0.0; writeln(Ord(r.SpecialType));
  r.Data := QWord($7FF0000000000000); writeln(Ord(r.SpecialType)); r.Data := QWord($7FF8000000000000); writeln(Ord(r.SpecialType));
  r.Data := 1; writeln(Ord(r.SpecialType), ' ', r.Exponent);
  r.Value := -2.75; writeln(Ord(r.SpecialType), ' ', r.Fraction:0:2, ' ', r.Exponent);
  r.BuildUp(True, 0, 3); writeln(r.Value:0:1);
  r.Sign := False; r.Exp := 1023 + 1; writeln(r.Value:0:1);
  s.Value := 3.0; writeln(s.Sign, ' ', s.Exp, ' ', s.Frac, ' ', s.Exponent, ' ', Ord(s.SpecialType));
  s.BuildUp(True, 1 shl 22, 0); writeln(s.Value:0:1);
end.
