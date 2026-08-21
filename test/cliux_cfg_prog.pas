{ Fixture for the pxx.cfg tier-3 rows in test-quick. It needs BOTH tiers at once:
  sysutils comes from the `home` line (the compiler is copied somewhere with no
  libraries above it) and cliux_cfg_unit from the `unitpath` line. Either tier
  silently doing nothing fails the build rather than printing a wrong answer. }
program cliux_cfg_prog;
uses sysutils, cliux_cfg_unit;
begin
  WriteLn(CliuxCfgGreeting, ' ', IntToStr(6 * 7));
end.
