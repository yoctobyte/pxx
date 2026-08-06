{ Format('%.Nf') must print the value's own digits at every magnitude.

  FmtFixed used to scale the whole value into an Int64 (`Trunc(v * 10^prec +
  0.5)`), which gave it two thresholds. Past 2^53 the scaled double could not
  hold the value exactly and the last digits were silently wrong — at prec = 2
  that starts at |v| ~ 9e13, which is money in cents, byte counts and
  nanosecond timestamps, not an exotic magnitude. Past 2^63 the Trunc wrapped
  to Int64.Min and EVERY value printed the same string, with a minus sign
  inside the fraction: '-92233720368547758.-8'. A large prec overflowed 10^prec
  the same way, so '%.20f' of 0.1 answered 0.00776627963145224192.
  bug-b-format-fixed-overflows-int64-and-loses-digits

  TWO oracles, for two different questions:
    - what the digits ARE — decimal.Decimal(float(x)) with ROUND_HALF_UP, the
      exact value of the double. FPC cannot answer this: it computes in
      Extended and prints its own approximation (its own '%.2f' of 1e30 is
      1000000000000000000020000000000.00, which is not the value).
    - what SHOULD be printed — FPC, measured. It sets the rounding rule
      (half AWAY FROM ZERO, so '%.2f' of 0.125 is '0.13' where glibc's
      half-to-even gives '0.12'), the Nan/+Inf/-Inf spellings, and the dropped
      sign once every digit has rounded away ('%.0f' of -0.4 is '0').

  Where the two disagree, exactness wins and the divergence is recorded:
  past 2^53 we print the true digits, and past ~1e300 we keep the fixed form
  where FPC bails to '1.0E+0300'. That display-policy call is
  decide-float-fixed-output-exact-or-fpc-17-digit-cap; printing digits that are
  not the value's digits is not an option under either answer. }
program lib_format_fixed;

uses sysutils;

var fails: Integer;

procedure Chk(const what, got, want: AnsiString);
begin
  if got = want then WriteLn(what, '=ok')
  else begin WriteLn(what, ' FAIL got=', got, ' want=', want); fails := fails + 1; end;
end;

type PD = ^Double;

var b: Int64; v: Double;
begin
  fails := 0;

  { ordinary range — unchanged, and FPC-identical }
  Chk('pi2',    Format('%.2f', [3.14159]), '3.14');
  Chk('pi3',    Format('%.3f', [3.14159]), '3.142');
  Chk('width',  Format('[%8.2f]', [3.5]), '[    3.50]');
  Chk('nodot',  Format('%.0f', [3.5]), '4');
  Chk('defprec',Format('%f', [3.5]), '3.50');
  Chk('neg',    Format('%.2f', [-1234.567]), '-1234.57');
  Chk('third',  Format('%.6f', [1.0 / 3.0]), '0.333333');

  { FPC's rounding rule is half AWAY FROM ZERO, on values that are exact in
    binary so the tie is a real tie }
  Chk('r125',   Format('%.2f', [0.125]), '0.13');
  Chk('r25',    Format('%.0f', [2.5]), '3');
  Chk('r35',    Format('%.0f', [3.5]), '4');
  Chk('r05',    Format('%.0f', [0.5]), '1');
  Chk('r025',   Format('%.1f', [0.25]), '0.3');
  Chk('carry',  Format('%.0f', [999.5]), '1000');

  { the sign goes once nothing is left of the value }
  Chk('mzero',  Format('%.0f', [-0.4]), '0');
  Chk('mzero4', Format('%.4f', [-0.00001]), '0.0000');
  Chk('zero',   Format('%.2f', [0.0]), '0.00');
  v := -0.0;
  Chk('negzero',Format('%.2f', [v]), '0.00');

  { REGIME 1 — past 2^53 the scaled double lost the last digits silently }
  Chk('e14',    Format('%.2f', [123456789012345.67]), '123456789012345.67');
  { the nearest double to 90071992547409.93 is ...9375, so .94 is the honest
    answer and the literal's own last digit is not }
  Chk('e14b',   Format('%.2f', [90071992547409.93]), '90071992547409.94');
  { 2^53 + 1 is not a double; the nearest one is 2^53, and that is what prints }
  Chk('p53',    Format('%.2f', [9007199254740993.0]), '9007199254740992.00');

  { REGIME 2 — past 2^63 every value printed '-92233720368547758.-8' }
  Chk('e17',    Format('%.2f', [1e17]), '100000000000000000.00');
  Chk('e18',    Format('%.3f', [1e18]), '1000000000000000000.000');
  Chk('e19',    Format('%.0f', [1e19]), '10000000000000000000');
  { exact values of the doubles, NOT the decimal literals }
  Chk('e23',    Format('%.0f', [1e23]), '99999999999999991611392');
  Chk('e25',    Format('%.0f', [1e25]), '10000000000000000905969664');
  Chk('e30',    Format('%.2f', [1e30]), '1000000000000000019884624838656.00');
  Chk('e30neg', Format('%.1f', [-1e30]), '-1000000000000000019884624838656.0');

  { a large precision overflowed 10^prec, and the answer is the double's exact
    tail — 0.1 really is 0.1000000000000000055511151231257827... }
  Chk('p20',    Format('%.20f', [0.1]), '0.10000000000000000555');
  Chk('p25',    Format('%.25f', [0.1]), '0.1000000000000000055511151');
  Chk('p30',    Format('%.30f', [1.0 / 3.0]),
                '0.333333333333333314829616256247');
  Chk('p30one', Format('%.30f', [1.0]), '1.000000000000000000000000000000');

  { small magnitudes: rounding still happens below the last printed place }
  Chk('tiny',   Format('%.2f', [1e-300]), '0.00');
  Chk('tiny2',  Format('%.3f', [0.0006]), '0.001');
  Chk('tiny3',  Format('%.1f', [0.06]), '0.1');
  Chk('tiny4',  Format('%.1f', [0.04]), '0.0');

  { grouping (%n) and currency (%m) run through the same routine }
  Chk('grp',    Format('%n', [1234567.891]), '1,234,567.89');
  Chk('grp3',   Format('%.3n', [-9876543.2105]), '-9,876,543.211');

  { non-finite: FPC's spellings, measured }
  b := Int64($7FF8000000000000); v := PD(@b)^;
  Chk('nan',    Format('%.2f', [v]), 'Nan');
  b := Int64($7FF0000000000000); v := PD(@b)^;
  Chk('inf',    Format('%.2f', [v]), '+Inf');
  b := Int64(-4503599627370496);  v := PD(@b)^;   { $FFF0000000000000 }
  Chk('neginf', Format('%.2f', [v]), '-Inf');

  if fails = 0 then WriteLn('FORMATFIXED OK')
  else WriteLn('FORMATFIXED FAILED ', fails);
end.
