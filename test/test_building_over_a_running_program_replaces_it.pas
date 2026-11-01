program test_building_over_a_running_program_replaces_it;
{ Built, started with `wait`, then built again while it runs: the second
  build must replace the file (ETXTBSY -> unlink + reopen), not report ok
  over a binary it never wrote. }
uses sysutils;
begin
  if ParamStr(1) = 'wait' then Sleep(5000)
  else WriteLn('replaced while running');
end.
