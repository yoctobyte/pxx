{ A routine stored into a procedural type of ANOTHER calling convention is
  refused, as FPC 3.2.2 refuses it ("Incompatible types"). It compiled, and the
  indirect call marshalled one convention into a prologue expecting the other:
  `f := @Twice; f(21.0)` printed 0.0 on x86-64 and Nan on i386. Four
  mismatches -- both directions, an argument and a record field -- and the check
  recovers, so one compile reports all four.
  bug-p-a-routine-assigned-to-a-procedural-type-of-another-calling-convention-is-accepted }
program test_procvar_calling_convention_mismatch_fail;
type
  TC = function(x: Double): Double; cdecl;
  TP = function(x: Double): Double;
  TR = record cb: TC; end;
function Twice(x: Double): Double; begin Twice := x * 2; end;
function Thrice(x: Double): Double; cdecl; begin Thrice := x * 3; end;
procedure Use(h: TC); begin WriteLn(h(1.0):0:1); end;
var f: TC; g: TP; r: TR;
begin
  f := @Twice;
  g := @Thrice;
  Use(@Twice);
  r.cb := @Twice;
end.
