program test_procedural_assign_calls_when_result_fits;
{ `x := F` where F is a free routine and x is procedural: the CALL of F, or the
  ADDRESS of F?

  Delphi's extended-syntax rule answers from the target: F is CALLED when its
  result fits x, and ADDRESSED when it does not. The method-pointer arm of the
  assignment path already asked that (MethodResultSatisfiesTarget); the
  free-routine arm beside it asked nothing and took the address of any routine
  name at all. Measured against fpc 3.2.2, both readings were wrong and in
  different ways -- `m := MakeSel` built a Code+Data pair out of MakeSel's own
  entry address and SEGFAULTED on the call through it, while `p := MakePl`
  silently called MakePl where FPC calls Plain, printing nothing at all.

  The four rows are the two-by-two: method pointer vs plain procedural, times
  result-fits (call it) vs plain-procedure (address it). The two address rows
  are the control -- they are what worked before and must keep working, so a
  fix that simply always called would fail here.

  Oracle: fpc 3.2.2 -Mdelphi -O1, byte-identical output.
  Found while fixing bug-p-result-is-not-a-method-pointer-lvalue, whose
  ProcRetProcSig column is what the plain-procedural half of the test reads. }
{$mode delphi}
type
  TSel = procedure of object;
  TPl  = procedure;
  TSvc = class procedure Pick; end;
procedure TSvc.Pick; begin writeln('picked'); end;
procedure Plain;     begin writeln('plain');  end;
var gs: TSvc;
function MakeSel: TSel; begin Result := gs.Pick; end;
function MakePl:  TPl;  begin Result := Plain;   end;
var m: TSel; p: TPl;
begin
  gs := TSvc.Create;

  { result FITS the target -> the routine is CALLED, and what it returns is
    what gets called through }
  m := MakeSel; m();
  p := MakePl;  p();

  { result does not fit -- these are not functions at all -- so the name is the
    routine's ADDRESS, which is the reading that already worked }
  p := Plain;   p();
  m := gs.Pick; m();
end.
