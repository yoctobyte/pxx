{ ESP: integer div and mod by ZERO give 0, and the program keeps running.

  The owner's ruling, 2026-09-24: "return 0 on esp, keep RE 200 on desktop" --
  an embedded device "should (try) to keep running, even if whatever unexpected
  input (sensor etc) produces a math error". Desktop keeps runtime error 200;
  the hosted rows in test-core still assert it.

  Every width and signedness goes through a different divide: LongInt,
  Int64 (the 64-bit software core on both ISAs), Cardinal. `side` proves each
  operand is evaluated exactly once. The `nonzero` rows are the control that
  the zero arm leaves a real divide alone, with Pascal's truncating signs.
  Expected output is a fixed file, not an x86-64 oracle, because the x86-64
  run halts at the first row, correctly.
  decide-int-div-zero-behavior-unification (DECIDED 2026-09-24) }
program test_esp_div_by_zero_yields_zero;
var a, b, calls: LongInt; qa, qb: Int64; ua, ub: Cardinal;
function F(x: LongInt): LongInt;
begin
  Inc(calls);
  F := x;
end;
begin
  calls := 0;
  a := 17; b := ParamCount;
  WriteLn('div32 ', a div b, ' mod32 ', a mod b);
  qa := 17; qb := ParamCount;
  WriteLn('div64 ', qa div qb, ' mod64 ', qa mod qb);
  ua := 17; ub := ParamCount;
  WriteLn('udiv ', ua div ub, ' umod ', ua mod ub);
  WriteLn('side ', F(17) div F(0), ' calls ', calls);
  b := 5; qb := 5;
  WriteLn('nonzero ', a div b, ' ', (-a) mod b, ' ', qa div qb, ' ', (-qa) mod qb, ' ', F(-17) div F(5));
  WriteLn('calls ', calls);
end.
