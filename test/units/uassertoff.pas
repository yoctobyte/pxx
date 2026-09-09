unit uassertoff;
{ A used unit that sets {$ASSERTIONS OFF} in its own source. It must read `off`
  under EVERY command-line polarity, including plain `-Sa`/default-on: a source
  directive outranks the flag, which is what makes the two FPC-testsuite rows
  that use Assert (tinterface4.pp, tprec23.pp — both open with {$ASSERTIONS ON})
  polarity-independent under --mimic-fpc.
  feature-p-assertions-switch-and-strict-default }
interface
function AssertState: ShortString;
implementation

{$ASSERTIONS OFF}

var
  Fired: Boolean;

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
