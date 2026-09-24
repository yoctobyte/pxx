program test_int64_counter_crosses_2pow32_on_32bit;
{ RUN ON A 32-bit TARGET (test-i386, test-riscv32). A green on x86-64 does
  NOT cover this file's subject: every row below is a 64-bit counter whose
  value crosses 2^32, and on a 64-bit host that is one register.

  Two lowerings, one symptom -- only the LOW WORD moved:
  - Inc/Dec: the desugared `x := x + step` node carried no width, so the add
    was 32-bit; `Inc(r)` from $FFFFFFFF gave 0, not 4294967296. This is what
    made NilPy's math.floor wrong on the ESP32.
  - a counted `for`: the counter was an untyped AN_IDENT, so its store, step
    and tests were native width; `for k := 4294967295 to 4294967296` never
    reached its limit (the Break below is what stops the broken version).
  Positive control at the time: pin af40370a8a91 on i386 prints nine of the
  eleven rows wrong -- `inc carry 0`, `for across 6 4`, `qword for 10 7`. }
var r: Int64; q: QWord; n: Integer; k: Int64; u: QWord;
begin
  r := $FFFFFFFF; Inc(r);    WriteLn('inc carry ', r);
  r := 0; Dec(r);            WriteLn('dec borrow ', r);
  r := 5; Dec(r, 7);         WriteLn('dec by 7 ', r);
  r := $FFFFFFFF; Inc(r, 2); WriteLn('inc by 2 ', r);
  n := 7; r := 5; Dec(r, n); WriteLn('dec by var ', r);
  q := $FFFFFFFF; Inc(q);    WriteLn('qword inc ', q);
  r := $100000000; Dec(r);   WriteLn('dec across ', r);

  n := 0;
  for k := 4294967295 to 4294967296 do begin Inc(n); if n > 5 then Break; end;
  WriteLn('for across ', n, ' ', k);
  n := 0;
  for k := 4294967296 downto 4294967294 do begin Inc(n); if n > 5 then Break; end;
  WriteLn('downto across ', n, ' ', k);
  n := 0;
  for k := -1 to 1 do Inc(n);
  WriteLn('for neg to pos ', n, ' ', k);
  n := 0;
  for u := QWord($FFFFFFFE) to QWord($100000001) do begin Inc(n); if n > 9 then Break; end;
  WriteLn('qword for ', n, ' ', u);
end.
