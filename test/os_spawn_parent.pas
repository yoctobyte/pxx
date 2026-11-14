{ SPDX-License-Identifier: Zlib }
{ ExecuteProcess: the child (os_spawn_child, path in argv[1]) gets the
  arguments split as on Linux, and its exit code comes back. test-windows. }
program os_spawn_parent;
uses SysUtils;
var r: Integer;
begin
  r := ExecuteProcess(ParamStr(1), 'a "b c" d\"e');
  WriteLn('exit code ', r);
end.
