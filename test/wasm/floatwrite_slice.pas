{ Writing a float on wasm32: the three RTL writers, all of which take the
  double by ADDRESS, so the value has to be spilled somewhere a callee can
  point at.

  The formatting itself is the shared RTL's and is not what this asserts --
  every digit here comes from the same PXXWriteFloat* routine the native build
  calls. What it asserts is the SPILL: that the address handed over is the
  right one, that it survives the call, and that it is not shared between two
  writes that are live at once.

  The last three cases are the ones that would pass with a frame-reserved
  scratch and fail on the shadow stack, or the reverse: two floats in one
  WriteLn, and a float whose value is itself a call (whose frame must land
  below the reservation rather than on top of it). }
program fw;
var d: Double; s: Single; i: Integer;
function Half(x: Double): Double; begin Half := x / 2.0; end;
begin
  d := 3.75;
  WriteLn(d);                    { native form }
  WriteLn(d:0:4);                { fixed }
  WriteLn(d:12:2);               { fixed, field width }
  WriteLn(d:15);                 { scientific, field width }
  d := -0.125;   WriteLn(d:0:6); WriteLn(d);
  d := 0.0;      WriteLn(d:0:3); WriteLn(d);
  d := 1e20;     WriteLn(d:0:2); WriteLn(d);
  d := 1e-20;    WriteLn(d:0:25); WriteLn(d);
  s := 2.5;      WriteLn(s:0:3); WriteLn(s);
  i := 7;        WriteLn(i:0:2);
  { two floats in ONE WriteLn: the reserved scratch must not be shared }
  WriteLn(3.5:0:2, ' ', 6.25:0:3);
  { a float whose value is a CALL: the callee's frame must land below the
    reservation, not on top of it }
  WriteLn(Half(9.0):0:4, ' ', Half(Half(16.0)):0:4);
  WriteLn('done');
end.
