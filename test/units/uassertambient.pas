unit uassertambient;
{ A used unit that says NOTHING about assertions, so it takes whatever the
  command line set. Half of the pair that separates "the flag reached every
  compilation unit" from "the flag reached the main program only" — the other
  half is uassertoff, which overrides it in its own source.
  feature-p-assertions-switch-and-strict-default }
interface
function AssertState: ShortString;
implementation

var
  Fired: Boolean;

{ The probe is the CONDITION's side effect, not a raised exception: assertions
  off compiles the call out CONDITION INCLUDED, so a condition that never ran
  is the observable, and it needs no sysutils and no try/except. Bump returns
  True so a live assertion passes rather than aborting the run. }
function Bump: Boolean;
begin
  Fired := True;
  Bump := True;
end;

function AssertState: ShortString;
begin
  Fired := False;
  Assert(Bump, 'unreachable: Bump always returns True');
  if Fired then AssertState := 'on' else AssertState := 'off';
end;

end.
