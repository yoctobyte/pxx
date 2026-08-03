{ write(v:w:d) must not print overflow debris.

  The value used to be scaled by 10^decimals in ONE multiply and rounded into
  an Int64, so `WriteLn(1e16:0:5)` and `WriteLn(267.5:0:17)` both overflowed and
  printed 2^63's own digits with a point pushed in — 92233720368547.75808, a
  plausible-looking number that is entirely debris
  (bug-b-writeln-float-with-17-decimals-prints-garbage).

  Every expectation below is FPC's output for the same program. The integer and
  fractional parts are now scaled separately, and digits past the 18th are
  zeros because a double carries no information there — which is what FPC does
  too (0.1:0:20 agrees on both). }
program lib_writefloat_fixed;

var fails: Integer;

procedure Chk(const what, got, want: AnsiString);
begin
  if got = want then WriteLn(what, '=ok')
  else begin WriteLn(what, ' FAIL got=', got, ' want=', want); fails := fails + 1; end;
end;

var y: Double; s: AnsiString;
begin
  fails := 0;
  y := 2.675 * 100.0;                 { exactly 267.5 }
  Str(y:0:2, s);   Chk('d2',  s, '267.50');
  Str(y:0:15, s);  Chk('d15', s, '267.500000000000000');
  Str(y:0:16, s);  Chk('d16', s, '267.5000000000000000');
  Str(y:0:17, s);  Chk('d17', s, '267.50000000000000000');
  Str(y:0:20, s);  Chk('d20', s, '267.50000000000000000000');
  Str(y:0:30, s);  Chk('d30', s, '267.500000000000000000000000000000');
  Str((-y):0:17, s); Chk('neg', s, '-267.50000000000000000');
  Str(0.1:0:20, s); Chk('tenth20', s, '0.10000000000000000000');
  Str(0.0:0:17, s); Chk('zero', s, '0.00000000000000000');
  { magnitudes where value*10^decimals passes 2^63 — all debris before }
  Str(1e15:0:5, s); Chk('e15', s, '1000000000000000.00000');
  Str(1e16:0:5, s); Chk('e16', s, '10000000000000000.00000');
  Str(1e17:0:5, s); Chk('e17', s, '100000000000000000.00000');
  Str(1e18:0:3, s); Chk('e18', s, '1000000000000000000.000');
  Str(1e-300:0:20, s); Chk('tiny', s, '0.00000000000000000000');
  { rounding still rounds, and a carry out of the fraction lands on the
    integer part }
  Str(0.5:0:0, s);  Chk('half0', s, '1');
  Str(1.5:0:0, s);  Chk('one50', s, '2');
  Str(2.5:0:0, s);  Chk('two50', s, '3');
  Str(0.999:0:2, s); Chk('carry', s, '1.00');
  Str((-0.999):0:2, s); Chk('negcarry', s, '-1.00');
  Str(9.9999:0:3, s); Chk('carry3', s, '10.000');
  { Str goes through StrFloat; WriteLn goes through the CODEGEN writer, which is
    a separate implementation of the same rules — the whole point is that they
    agree, so both are exercised. }
  WriteLn(y:0:2);
  WriteLn(y:0:17);
  WriteLn(y:0:20);
  WriteLn(1e16:0:5);
  WriteLn(0.1:0:20);
  WriteLn(0.5:0:0);
  WriteLn(1.5:0:0);
  WriteLn(2.5:0:0);
  WriteLn(0.999:0:2);
  WriteLn((-y):0:17);
  WriteLn(y:30:5);
  if fails = 0 then WriteLn('WRITEFLOAT OK')
  else WriteLn('WRITEFLOAT FAILED ', fails);
end.
