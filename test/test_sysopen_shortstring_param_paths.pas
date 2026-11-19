program test_sysopen_shortstring_param_paths;
{ SysOpen through a frozen-string path in every place the path can LIVE: a
  local, a string[N], a value parameter and a var parameter, beside the global
  test_sysopen_shortstring_path.pas covers. A parameter's slot holds the
  caller's buffer address rather than the buffer, so it takes a different
  branch in each backend; riscv32 and xtensa opened the slot's bytes and
  failed until 2026-11-19, and the global-only test could not see it.
  bug-a-three-targets-refuse-a-shortstring-sysopen-path-four-implement-it }
function OpenVal(p: ShortString): Boolean;
var fd: Integer;
begin fd := SysOpen(p, 0); Result := fd >= 0; if fd >= 0 then SysClose(fd); end;
function OpenVar(var p: ShortString): Boolean;
var fd: Integer;
begin fd := SysOpen(p, 0); Result := fd >= 0; if fd >= 0 then SysClose(fd); end;
procedure Local;
var p: ShortString; q: string[20]; fd: Integer;
begin
  p := '/etc/passwd'; fd := SysOpen(p, 0); WriteLn('local ', fd >= 0); if fd >= 0 then SysClose(fd);
  q := '/etc/passwd'; fd := SysOpen(q, 0); WriteLn('str20 ', fd >= 0); if fd >= 0 then SysClose(fd);
  p := '/nonexistent/x'; WriteLn('miss ', SysOpen(p, 0) >= 0);
end;
var g: ShortString;
begin
  Local;
  g := '/etc/passwd';
  WriteLn('val ', OpenVal(g), ' var ', OpenVar(g), ' after ', g);
end.
