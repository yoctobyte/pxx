program test_class_cast_field;
{ Regression for bug-subclass-field-offset-calculation + method-call-on-hard-cast:
  a hard class typecast TClass(expr) must resolve field offsets against TClass
  (incl. inherited base size) for reads AND writes, AND dispatch method calls
  (static + virtual) on it — not resolve everything at offset 0. }
type
  TComponent = class
    FName: Integer;
    function Tag: Integer; virtual;
  end;
  TControl = class(TComponent)
    FHandle: Int64;
    procedure SetHandle(h: Int64);
    function GetHandle: Int64;
    function Tag: Integer; override;
  end;
function TComponent.Tag: Integer; begin Result := 1; end;
function TControl.Tag: Integer; begin Result := 2; end;
procedure TControl.SetHandle(h: Int64); begin FHandle := h; end;
function TControl.GetHandle: Int64; begin Result := FHandle; end;
var c: TComponent; ctl: TControl; h: Int64; n: Integer;
begin
  ctl := TControl.Create;
  ctl.FName := 7; ctl.FHandle := 166408768;
  c := ctl;
  { field read through cast — own field of the subclass }
  h := TControl(c).FHandle;  writeln(h);          { 166408768 }
  { field read through cast — inherited field }
  n := TControl(c).FName;    writeln(n);          { 7 }
  { field write through cast }
  TControl(c).FHandle := 42; writeln(ctl.FHandle); { 42 }
  TControl(c).FName := 99;   writeln(ctl.FName);   { 99 }
  { method call through cast — statement (with arg) and expression }
  TControl(c).SetHandle(555);  writeln(ctl.FHandle); { 555 }
  h := TControl(c).GetHandle;  writeln(h);           { 555 }
  { virtual method through hard cast to base — dispatches dynamically }
  n := TComponent(ctl).Tag;  writeln(n);             { 2 }
end.
