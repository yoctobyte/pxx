{ SPDX-License-Identifier: Zlib }
{ The child for os_spawn_parent.pas/.npy (test-windows): prints its arguments,
  echoes stdin when the first is "echo", and exits with its argument count. }
program child;
var i: Integer; s: string;
begin
  Write('child argc=', ParamCount);
  for i := 1 to ParamCount do Write(' [', ParamStr(i), ']');
  WriteLn;
  if ParamCount > 0 then
    if ParamStr(1) = 'echo' then
      while not Eof do begin ReadLn(s); WriteLn('got: ', s); end;
  Halt(ParamCount);
end.
