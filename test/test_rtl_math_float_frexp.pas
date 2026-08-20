program test_rtl_math_float_frexp;
{$mode objfpc}{$H+}
{ Math.Float, Frexp and Ldexp -- RTL names FPC code calls that this RTL did not
  have, found by compiling rtl-generics (feature-pascal-corpus-generics), whose
  default Extended comparer hashes SizeOf(Float) bytes after splitting the value
  with Frexp.

  Two things are asserted here and they are different:
    - Frexp/Ldexp NUMERICS, checked against FPC 3.2.2 (this file runs unchanged
      under it). x = mantissa * 2**exponent exactly, with 0.5 <= |mantissa| < 1,
      including the subnormal range where the naive bit-extraction reads a
      biased exponent of 0.
    - SizeOf(Math.Float) is answerable AT ALL. It is 8 here and 10 under FPC,
      which is not a bug: FPC's Float is "the widest float the target supports"
      and this RTL aliases Extended to Double, as lib/rtl/math.pas's header
      says. So the size is deliberately NOT compared against the oracle -- what
      regressed was `SizeOf(Math.Float)` being a COMPILE ERROR, because the
      intrinsic stripped only a `System.` qualifier and no other unit's. }
uses math;

var
  total, okc: Integer;

procedure Check(const name: AnsiString; ok: Boolean);
begin
  total := total + 1;
  if ok then
  begin
    okc := okc + 1;
    writeln('ok ', name);
  end
  else
    writeln('FAIL ', name);
end;

{ the defining identity, plus the normalisation range }
{ `m: Float` and not `Double` deliberately: it is what keeps this file runnable
  under FPC unchanged, where Frexp's var-parameter is Extended and a Double
  argument is a hard error ("call by var has to match exactly"). Under pxx the
  two spellings are the same type. }
procedure CheckSplit(const name: AnsiString; x: Double);
var m: Float; back: Double; e: Integer;
begin
  Frexp(x, m, e);
  back := Ldexp(m, e);
  Check(name, (back = x) and (Abs(m) >= 0.5) and (Abs(m) < 1.0));
end;

var
  m: Float;
  e: Integer;
begin
  total := 0; okc := 0;

  { the width the comparer hashes: any unit qualifier on a type name }
  { >= and not =, so this file gives the same 14/14 under FPC: Float is 10 bytes
    there and 8 here, the deliberate divergence the header explains. What is
    being asserted is that the QUALIFIED name resolves at all -- it was a
    compile error, not a wrong number. }
  Check('sizeof-qualified-type', SizeOf(Math.Float) >= SizeOf(Double));
  Check('sizeof-plain-float', SizeOf(Float) = SizeOf(Math.Float));

  Frexp(8.0, m, e);
  Check('frexp-8', (m = 0.5) and (e = 4));
  Frexp(-8.0, m, e);
  Check('frexp-neg8', (m = -0.5) and (e = 4));
  Frexp(1.0, m, e);
  Check('frexp-1', (m = 0.5) and (e = 1));
  Frexp(0.0, m, e);
  Check('frexp-zero', (m = 0.0) and (e = 0));

  CheckSplit('split-3', 3.0);
  CheckSplit('split-small', 1.0 / 1024.0);
  CheckSplit('split-tiny', 5.0e-300);
  { subnormal: the biased exponent field is 0, so the value has to be scaled up
    first or the answer is silently wrong }
  CheckSplit('split-subnormal', 5.0e-320);
  CheckSplit('split-huge', 1.0e300);

  Check('ldexp-round-trip', Ldexp(0.75, 3) = 6.0);
  Check('ldexp-negative', Ldexp(0.75, -3) = 0.09375);
  Check('ldexp-zero-exp', Ldexp(1.25, 0) = 1.25);

  writeln('total ok ', okc, ' / ', total);
end.
