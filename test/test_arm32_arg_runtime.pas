program test_arm32_arg_runtime;

var
  managed: AnsiString;
  fixed: string;

begin
  writeln(ParamCount);
  managed := ParamStr(1);
  writeln(managed);
  ArgStr(2, fixed);
  writeln(fixed);
end.
