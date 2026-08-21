{ Fixture for the pxx.cfg tier-3 rows in test-quick. Deliberately a UNIT that
  lives nowhere the compiler could find on its own: the test copies it under a
  scratch directory whose only route in is a `unitpath` line in a pxx.cfg. }
unit cliux_cfg_unit;
interface
function CliuxCfgGreeting: AnsiString;
implementation
function CliuxCfgGreeting: AnsiString;
begin
  CliuxCfgGreeting := 'cliux cfg unit';
end;
end.
