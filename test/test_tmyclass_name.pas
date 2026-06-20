{ Regression: a user class named TMyClass (formerly a hardcoded builtin record
  REC_TMYCLASS) resolves as a normal user class, incl. method calls.
  bug-compiler-tmyclass-hardcoded-clash. }
program test_tmyclass_name;
type
  TMyClass = class
    v: Integer;
    function GetV: Integer;
    procedure SetV(n: Integer);
  end;
function TMyClass.GetV: Integer; begin Result := v; end;
procedure TMyClass.SetV(n: Integer); begin v := n; end;
var o: TMyClass;
begin
  o := TMyClass.Create;
  o.SetV(77);
  o.v := o.GetV + 1;
  writeln(o.GetV);
end.
