program test_p_a_class_beats_a_used_units_routine_before_a_dot;
{ A class declared in the program beats a used unit's routine of the same
  name in front of `.`: `TB.Create` constructs the program's TB instead of
  failing with "class method not found (Create)". The kernel translators
  (winabi has a TB, fbsdabi a PathIs) made this bite on --os=nt and the BSDs.
  The routines stay reachable unit-qualified.
  bug-p-a-source-class-loses-to-a-used-units-routine-before-a-dot }
{$mode objfpc}
uses routinenames;
type
  TA = class(TObject)
    function Nm: AnsiString; virtual;
  end;
  TB = class(TA)
    function Nm: AnsiString; override;
  end;
  Worker = class(TA)
    class function Kind: AnsiString;
  end;
function TA.Nm: AnsiString; begin Result := 'TA'; end;
function TB.Nm: AnsiString; begin Result := 'TB'; end;
class function Worker.Kind: AnsiString; begin Result := 'worker-class'; end;
var a: TA; p: Int64;
begin
  a := TB.Create;
  WriteLn(a.Nm, ' ', a.ClassName);
  a.Free;
  a := Worker.Create;
  WriteLn(a.Nm, ' ', Worker.Kind);
  a.Free;
  p := 1;
  routinenames.TB(p, 2);
  WriteLn(p, ' ', routinenames.Worker);
end.
