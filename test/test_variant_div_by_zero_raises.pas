program test_variant_div_by_zero_raises;
{ `div` / `mod` by zero on Variants raises EDivByZero, as it already did on plain
  Integers and as FPC does for both.

  It used to do neither: x86-64 reached a raw idiv and died on SIGFPE with a core
  dump -- uncatchable, no message, in a program whose `except` was right there --
  while i386/arm32 answered -1 and aarch64 answered 0. Nothing was checking, so
  each target's divide instruction did whatever it does with a zero divisor.

  The non-zero rows matter as much as the raising ones: the fix inserts a test in
  front of every variant div/mod, and a test that only checked the zero case
  would pass even if it broke ordinary division.

  Oracle: fpc 3.2.2 -Mobjfpc -O1 raises on every row marked as raising and
  produces every value below. }
{$mode objfpc}{$H+}
uses variants, sysutils;
var
  a, b, c: Variant;
  ia, ib, ic: Integer;
  fails: Integer;

procedure ChkVal(const what: string; got, want: Int64);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

begin
  fails := 0;

  { --- ordinary division still works --- }
  a := 7; b := 2;  c := a div b;  ChkVal('7 div 2', Int64(c), 3);
  a := 7; b := 2;  c := a mod b;  ChkVal('7 mod 2', Int64(c), 1);
  a := -7; b := 2; c := a div b;  ChkVal('-7 div 2', Int64(c), -3);
  a := 7; b := 2.0; c := a div b; ChkVal('7 div 2.0', Int64(c), 3);

  { --- ...and a zero divisor raises rather than trapping or inventing --- }
  a := 1; b := 0;
  try c := a div b; writeln('FAIL int div 0: got ', Int64(c)); Inc(fails);
  except on e: Exception do ; end;

  a := 1; b := 0;
  try c := a mod b; writeln('FAIL int mod 0: got ', Int64(c)); Inc(fails);
  except on e: Exception do ; end;

  { the VT_DOUBLE arm truncates to integers first and has its own div site }
  a := 1.5; b := 0.0;
  try c := a div b; writeln('FAIL dbl div 0: got ', Int64(c)); Inc(fails);
  except on e: Exception do ; end;

  a := 1.5; b := 0.0;
  try c := a mod b; writeln('FAIL dbl mod 0: got ', Int64(c)); Inc(fails);
  except on e: Exception do ; end;

  { a zero that arrived as a Double but is integer-valued }
  a := 6; b := 0.0;
  try c := a div b; writeln('FAIL mixed div 0: got ', Int64(c)); Inc(fails);
  except on e: Exception do ; end;

  { --- the plain-Integer path stays working. Its div-by-ZERO is deliberately
        NOT asserted here: measured against the PINNED binary, plain `ia div 0`
        answers -1 on i386/arm32 and 0 on aarch64 -- the pre-divide check is
        emitted by the x86-64 backend and by no other. That is a separate,
        pre-existing, wider defect, and it carries its own assertion in
        bug-a-the-div-by-zero-check-is-emitted-on-x86-64-only. Asserting it here
        would make this test pass natively while staying wrong on four
        targets. --- }
  ia := 7; ib := 2; ic := ia div ib; ChkVal('plain 7 div 2', ic, 3);
  ia := 7; ib := 2; ic := ia mod ib; ChkVal('plain 7 mod 2', ic, 1);

  if fails = 0 then
    writeln('ALL OK')
  else
    writeln('FAILURES: ', fails);
end.
