program test_unhandled_exception_exit_code;
{$mode objfpc}{$H+}
uses SysUtils;

procedure DeepRaise;
begin
  raise Exception.Create('from a nested frame');
end;

var a, b: Integer;
begin
  WriteLn('before');
  if ParamStr(1) = 'proc' then
    DeepRaise
  else if ParamStr(1) = 'divzero' then
  begin
    a := 1; b := 0;
    WriteLn(a div b);
  end
  else
    raise Exception.Create('unhandled');
  WriteLn('unreached');
end.
