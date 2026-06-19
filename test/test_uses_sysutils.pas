program TestUsesSysutils;
{ `uses sysutils` is no longer hard-skipped: a real lib/rtl/sysutils.pas (added
  by track B) loads normally; with no such source on the path it stays a
  graceful no-op so builtin-only FPC code keeps compiling. This test covers the
  no-op fallback (no sysutils source committed yet). Regression for
  bug-sysutils-unit-hard-skipped. }
uses sysutils;
begin
  WriteLn('sysutils noop ok');
end.
