program test_env_pascal;
{ sysutils' FPC-spelled environment accessors, over /proc/self/environ.
  The harness sets PXX_ENV_PROBE=hello. }
uses sysutils;
begin
  WriteLn(GetEnvironmentVariable('PXX_ENV_PROBE'));
  WriteLn('[', GetEnvironmentVariable('NOT_SET_AT_ALL'), ']');
  if GetEnvironmentVariableCount > 0 then WriteLn('count ok') else WriteLn('count EMPTY');
end.
