program test_class_cast_field;
{ Regression for bug-subclass-field-offset-calculation: a hard class typecast
  TClass(expr).field must resolve the field offset against TClass (incl. inherited
  base size), for both reads and writes — not at offset 0. }
type
  TComponent = class
    FName: Integer;
  end;
  TControl = class(TComponent)
    FHandle: Int64;
  end;
var c: TComponent; ctl: TControl; h: Int64; n: Integer;
begin
  ctl := TControl.Create;
  ctl.FName := 7; ctl.FHandle := 166408768;
  c := ctl;
  { read through cast — own field of the subclass }
  h := TControl(c).FHandle;  writeln(h);          { 166408768 }
  { read through cast — inherited field }
  n := TControl(c).FName;    writeln(n);          { 7 }
  { write through cast }
  TControl(c).FHandle := 42; writeln(ctl.FHandle); { 42 }
  TControl(c).FName := 99;   writeln(ctl.FName);   { 99 }
end.
