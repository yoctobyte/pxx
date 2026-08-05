program test_writeln_float_exact;
{ Regression: writeln(Double) and Str(F,S) must be CORRECTLY ROUNDED — the same
  17 significant digits FPC and CPython produce.

  Four copies of a normalise-by-repeated-division loop (`while x >= 10 do
  x := x / 10`) each carried one rounding per iteration — ~100 of them for
  1e100 — putting the error inside the 17 digits being printed. For 1e200 it
  moved the EXPONENT: a value just UNDER 1e200 printed as 1.0000000000000007E+200
  instead of 9.9999999999999997E+199. writeln and Str even disagreed with each
  other (...007 vs ...006 for 1e100) — two spellings of one conversion in one
  file.

  Replaced by an exact decimal expansion (PxxSciDigits17 in builtinheap): every
  finite double IS a finite decimal, so the digits are real digits, rounded
  half-to-even on an exact remainder. The two native emitters (x86-64, aarch64)
  now shim onto the same runtime routine, so there is ONE implementation
  instead of four.

  Values verified against BOTH FPC and CPython (f'{v:.16e}') — the ticket
  requires both to agree before either is trusted.
  bug-a-writeln-float-exponent-form-not-correctly-rounded }
var d: Double; s: string;
begin
  { the six rows from the ticket }
  d := 1e30;                   writeln(d);
  d := 1e100;                  writeln(d);
  d := 1e200;                  writeln(d);   { the wrong-EXPONENT row }
  d := 1e-20;                  writeln(d);
  d := 123456789012345.0;      writeln(d);
  d := 2.5e100;                writeln(d);
  { Str must now AGREE with writeln }
  d := 1e100; Str(d, s);       writeln(s);
  { edges: zero, negative zero, subnormals, the extremes }
  d := 0.0;                    writeln(d);
  d := 1.0;                    writeln(d);
  d := -2.5;                   writeln(d);
  d := 5e-324;                 writeln(d);   { smallest subnormal, 767-digit case }
  d := 1e-320;                 writeln(d);
  d := 1.7976931348623157e308; writeln(d);   { max double }
  d := 0.1;                    writeln(d);
  d := 9.999999999999999e99;   writeln(d);
  writeln('OK');
end.
