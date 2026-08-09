{ The three rounding DEFAULTS, pinned. Read this before "fixing" any of them.

  pxx has three frontends with three DIFFERENT rounding rules, and each one is
  correct for its own language. Found from any single side, the disagreement
  looks like a bug. It is not:

    Pascal  Round    ties-to-even          matches fpc
    C       round()  half-away-from-zero   matches gcc
    NilPy   round()  ties-to-even          matches CPython

  Every row below was measured against the real reference implementation on the
  same machine (bug-b-rounding-api-gaps-setroundmode-roundto-lround). Making
  them agree with each other would break all three.

  This file pins the PASCAL side plus the RoundTo family. The C side is pinned
  by test/cmath_lround.c and the NilPy side by the nilpy suite.

  Why Pascal is ties-to-even at all: `Round` is not an algorithm, it is a
  float->int conversion in the current hardware rounding mode, and that mode
  defaults to nearest-even. pxx does all double arithmetic in SSE, so the mode
  lives in MXCSR. There is no Pascal-side SetRoundMode yet — the intrinsic
  exists but is C-only and a no-op off x86-64; see the ticket. }
program lib_rounding_contract;

uses math, sysutils;

var
  failures: Integer;

procedure CheckI(got, want: Int64; const what: string);
begin
  if got <> want then
  begin
    writeln('FAIL: ', what, ' got ', got, ' want ', want);
    failures := failures + 1;
  end;
end;

procedure CheckF(got, want: Double; const what: string);
begin
  { exact compare: these are all representable results of a rounding op }
  if got <> want then
  begin
    writeln('FAIL: ', what, ' got ', got:0:6, ' want ', want:0:6);
    failures := failures + 1;
  end;
end;

var
  h, t: Double;
begin
  failures := 0;

  { ---- Round: TIES TO EVEN, identical to fpc. Runtime values, because a
         literal argument gets constant-folded and would not exercise the
         conversion at all. ---- }
  h := 0.5;  CheckI(Round(h), 0, 'Round(0.5)');
  h := 1.5;  CheckI(Round(h), 2, 'Round(1.5)');
  h := 2.5;  CheckI(Round(h), 2, 'Round(2.5) — NOT 3, ties-to-even');
  h := 3.5;  CheckI(Round(h), 4, 'Round(3.5)');
  h := -0.5; CheckI(Round(h), 0, 'Round(-0.5)');
  h := -1.5; CheckI(Round(h), -2, 'Round(-1.5)');
  h := -2.5; CheckI(Round(h), -2, 'Round(-2.5) — NOT -3');

  { ---- Trunc: toward zero ---- }
  h := 2.7;  CheckI(Trunc(h), 2, 'Trunc(2.7)');
  h := -2.7; CheckI(Trunc(h), -2, 'Trunc(-2.7)');

  { ---- Floor/Ceil return INTEGER, as FPC's do, with Floor64/Ceil64 for the
         64-bit range. They are NOT C's floor()/ceil(), which return double and
         live in crtl — the two coexist and must keep giving their own answers
         (test/cmath_no_pascal_hijack.c watches the C side). ---- }
  h := -2.7; CheckI(Floor(h), -3, 'Floor(-2.7)');
  h := -2.7; CheckI(Ceil(h), -2, 'Ceil(-2.7)');
  h := 2.7;  CheckI(Floor(h), 2, 'Floor(2.7)');
  h := 2.7;  CheckI(Ceil(h), 3, 'Ceil(2.7)');
  h := -3.0; CheckI(Floor(h), -3, 'Floor(-3.0) exact');
  h := -3.0; CheckI(Ceil(h), -3, 'Ceil(-3.0) exact');
  { the 64-bit pair exists BECAUSE the Integer one overflows past 2^31 — the
    same limitation FPC has, which is why FPC ships both }
  h := 4503599627370495.0;
  CheckI(Floor64(h), 4503599627370495, 'Floor64 past 2^31');
  h := -4503599627370495.0;
  CheckI(Floor64(h), -4503599627370495, 'Floor64 negative past 2^31');

  { ---- RoundTo: FPC's formula, Round(v / 10^d) * 10^d. The 2.675 row is the
         one that catches a re-derivation: dividing by 0.01 lands just ABOVE
         the tie and gives 2.68, where multiplying by 100 lands just below and
         gives 2.67. FPC says 2.68. ---- }
  t := 2.675;   CheckF(RoundTo(t, -2), 2.68, 'RoundTo(2.675, -2) = 2.68');
  t := 1.005;   CheckF(RoundTo(t, -2), 1.0, 'RoundTo(1.005, -2)');
  t := 0.125;   CheckF(RoundTo(t, -2), 0.12, 'RoundTo(0.125, -2) — ties-to-even');
  t := 1.2345;  CheckF(RoundTo(t, -2), 1.23, 'RoundTo(1.2345, -2)');
  t := -1.2345; CheckF(RoundTo(t, -2), -1.23, 'RoundTo(-1.2345, -2)');
  t := 123.456; CheckF(RoundTo(t, 1), 120.0, 'RoundTo(123.456, 1) — tens');
  t := 125.0;   CheckF(RoundTo(t, 1), 120.0, 'RoundTo(125, 1) — ties-to-even at tens');
  t := 135.0;   CheckF(RoundTo(t, 1), 140.0, 'RoundTo(135, 1)');

  { ---- SimpleRoundTo: half-AWAY-from-zero. Differs from RoundTo on exactly
         the tie, which is the whole reason FPC ships both. ---- }
  t := 0.125;   CheckF(SimpleRoundTo(t, -2), 0.13, 'SimpleRoundTo(0.125, -2) = 0.13');
  t := 2.675;   CheckF(SimpleRoundTo(t, -2), 2.68, 'SimpleRoundTo(2.675, -2)');
  t := 1.005;   CheckF(SimpleRoundTo(t, -2), 1.0, 'SimpleRoundTo(1.005, -2)');
  t := 1.2345;  CheckF(SimpleRoundTo(t, -2), 1.23, 'SimpleRoundTo(1.2345, -2)');
  t := -1.2345; CheckF(SimpleRoundTo(t, -2), -1.23, 'SimpleRoundTo(-1.2345, -2)');

  if failures = 0 then writeln('ROUNDING OK')
  else writeln('ROUNDING ', failures, ' FAILURES');
end.
