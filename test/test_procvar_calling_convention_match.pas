{ The accepted half of test_procvar_calling_convention_mismatch_fail: when the
  routine and the procedural type agree, both conventions call correctly --
  through a variable, an argument and a record field.
  bug-p-a-routine-assigned-to-a-procedural-type-of-another-calling-convention-is-accepted }
program test_procvar_calling_convention_match;
type
  TC = function(x: Double): Double; cdecl;
  TP = function(x: Double): Double;
  TR = record cb: TC; end;
function Twice(x: Double): Double; cdecl; begin Twice := x * 2; end;
function Thrice(x: Double): Double; begin Thrice := x * 3; end;
procedure Use(h: TC); begin WriteLn(h(1.5):0:1); end;
var f: TC; g: TP; r: TR;
begin
  f := @Twice; g := @Thrice; r.cb := @Twice;
  WriteLn(f(21.0):0:1, ' ', g(2.0):0:1, ' ', r.cb(4.0):0:1);
  Use(@Twice);
end.
