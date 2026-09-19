program test_sys_intrinsic_as_argument;
{ SysOpen / SysRead / SysWrite return an Integer, and a call to one must be
  usable as an ARGUMENT, not only as an assignment source. The intrinsic's
  AN_CALL node carried no type, so overload resolution read it as "unknown"
  and refused `Take(syswrite(...), n)` with "argument types: (unknown,
  Integer)". The values below are not defaults: 2 bytes written, a negative
  errno for a missing path, and 0 for an empty read. }
var b: array[0..3] of Byte; p: string;
procedure Take(const what: string; got: Integer);
begin
  WriteLn(what, ' ', got);
end;
function Neg(v: Integer): Boolean;
begin
  Neg := v < 0;
end;
begin
  b[0] := 65; b[1] := 10;
  Take('write', syswrite(2, b, 2));
  p := '/nonexistent/pxx-sys-intrinsic';
  WriteLn('open-missing ', Neg(sysopen(p, 0)));
  Take('read', sysread(0, b, 0));
  WriteLn('SYS INTRINSIC AS ARGUMENT OK');
end.
