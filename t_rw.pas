program t_rw;
uses typinfo, classes_lite, resources, lfm, gtk3, controls, stdctrls, extctrls, forms;
{$R TMainForm t_rw.lfm}
type TMainForm = class(TForm) constructor Create; end;
constructor TMainForm.Create;
begin Self.HandleNeeded; InitInheritedComponent(Self, 'TMainForm'); end;
var f: TMainForm;
begin
  Application := TApplication.Create; Application.Initialize;
  f := TMainForm.Create;
  Application.MainForm := f;
  Application.Run;
end.
