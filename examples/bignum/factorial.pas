{ SPDX-License-Identifier: 0BSD }
program Factorial;
{ Arbitrary-precision factorial — demo + deterministic oracle for lib/rtl/bignum.

  Uses BigFromInt + BigMulSmall + BigToStr (the verified bignum core). Prints a
  few small factorials and the headline oracle: 1000! has exactly 2568 digits,
  begins 4023872600..., and ends in 249 zeros. Integer-deterministic, so the
  output is byte-identical across targets. Track B; pinned stable. }

uses bignum, sysutils;

var
  acc: TBigInt;
  i, zeros: Integer;
  s: AnsiString;
begin
  { All in the main body, each factorial its own loop. Kept out of a helper
    procedure on purpose: a proc with a TBigInt local miscomputes on its first
    call (proc-local managed records aren't zero-initialised on entry -- see
    bug-proc-local-managed-record-uninit). }
  acc := BigFromInt(1);
  for i := 2 to 5 do acc := BigMulSmall(acc, i);
  writeln('5! = ', BigToStr(acc));                     { 120 }

  acc := BigFromInt(1);
  for i := 2 to 10 do acc := BigMulSmall(acc, i);
  writeln('10! = ', BigToStr(acc));                    { 3628800 }

  acc := BigFromInt(1);
  for i := 2 to 20 do acc := BigMulSmall(acc, i);
  writeln('20! = ', BigToStr(acc));                    { 2432902008176640000 }

  { 1000! oracle }
  acc := BigFromInt(1);
  for i := 2 to 1000 do acc := BigMulSmall(acc, i);
  s := BigToStr(acc);

  zeros := 0;
  i := Length(s);
  while (i >= 1) and (s[i] = '0') do
  begin
    zeros := zeros + 1;
    i := i - 1;
  end;

  writeln('1000! digits      = ', IntToStr(Length(s)));   { 2568 }
  writeln('1000! first 10    = ', Copy(s, 1, 10));         { 4023872600 }
  writeln('1000! trailing 0s = ', IntToStr(zeros));        { 249 }
end.
