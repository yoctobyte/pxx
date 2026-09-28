program test_div_by_a_run_time_zero_raises_on_wasm32;

{ Integer div and mod by a divisor that is zero at RUN time must raise
  EDivByZero (RE 200 without SysUtils), the same as on every native backend.
  On wasm32, the div/rem instruction trapped first ("wasm trap: integer divide
  by zero", exit 134), which no try/except can catch. Covers Integer, Int64,
  Cardinal and QWord; a divide inside a call argument; and one on the right of
  a short-circuit `and`. Checked against FPC 3.2.2.
  bug-a-wasm32-div-by-a-run-time-zero-traps-instead-of-raising }
{$mode objfpc}
uses SysUtils;
var a, b: Integer; x, y: Int64; c, d: Cardinal; q, r: QWord; n: Integer;

function Id(v: Integer): Integer; begin Id := v; end;

procedure Try1(const tag: AnsiString; k: Integer);
begin
  try
    case k of
      0: WriteLn(a div b);
      1: WriteLn(a mod b);
      2: WriteLn(x div y);
      3: WriteLn(x mod y);
      4: WriteLn(c div d);
      5: WriteLn(c mod d);
      6: WriteLn(q div r);
      7: WriteLn(q mod r);
      8: WriteLn(Id(7) + Id(a div b) * 3);
      9: if (a > 0) and (a div b > 0) then WriteLn('yes') else WriteLn('no');
    end;
    WriteLn(tag, ' not reached');
  except
    on E: EDivByZero do WriteLn(tag, ' caught ', E.ClassName, ' ', E.Message);
  end;
end;

begin
  a := 7; b := 0; x := 7; y := 0; c := 7; d := 0; q := 7; r := 0;
  for n := 0 to 9 do Try1('k' + IntToStr(n), n);
  b := 2; y := 2; d := 2; r := 2;
  WriteLn(a div b, ' ', a mod b, ' ', x div y, ' ', x mod y, ' ', c div d, ' ', c mod d, ' ', q div r, ' ', q mod r);
  b := -2; WriteLn(-7 div b, ' ', -7 mod b);
end.
