program test_the_assertions_polarity_follows_the_command_line;
{ feature-p-assertions-switch-and-strict-default.

  ONE source, FOUR command lines. The Makefile compiles this file with no flag,
  with -Sa, with --no-assertions and with --mimic-fpc, and asserts a DIFFERENT
  expected line for two of them — which is the whole claim: the flag sets the
  starting polarity of every compilation unit, and a source directive outranks
  it everywhere.

  WHY --mimic-fpc IS IN HERE AT ALL: FPC compiles Assert out unless -Sa, so a
  program whose only divergence from an FPC build was a failing assertion exited
  1 under --mimic-fpc and 0 under `fpc -Mobjfpc`. Measured 2026-09-09 before the
  fix; the `ambient=off` row below is that difference, asserted.

  THE PROBE IS THE CONDITION'S SIDE EFFECT, not a raised exception: assertions
  off compiles the call out condition included, so "did Bump run" is the
  observable and the test needs neither sysutils nor a nonzero exit. Every Bump
  returns True, so no row aborts and a row that fails still prints its
  neighbours.

  THE ROWS AND WHAT EACH ONE CAN FAIL AT:
    ambient       no directive above it — the only row the flag may move. If the
                  flag were inert this reads `on` in all four runs and two of
                  the four Makefile rows fail.
    dir-on        {$ASSERTIONS ON} above it — must read `on` in ALL FOUR runs.
                  If --mimic-fpc wrongly outranked the source, this reads `off`.
    dir-off       {$C-} above it — must read `off` in all four, including the
                  two where the ambient is on. This is what proves the directive
                  half still works after the CLI half was added.
    unit-ambient  a used unit that says nothing — must track the flag, proving
                  the polarity reaches units and not just the main program.
    unit-off      a used unit with its own {$ASSERTIONS OFF} — `off` in all
                  four, the per-unit override.

  `dir-off` and `unit-off` expecting `off` is deliberately NOT the do-nothing
  answer here, because `ambient` and `dir-on` expecting `on` in the same run
  prove the machinery is live. A build where Assert did nothing at all fails
  those two rather than passing quietly. }

uses uassertambient, uassertoff;

var
  Fired: Boolean;

function Bump: Boolean;
begin
  Fired := True;
  Bump := True;
end;

function State: ShortString;
begin
  if Fired then State := 'on' else State := 'off';
end;

function Ambient: ShortString;
begin
  Fired := False;
  Assert(Bump, 'unreachable: Bump always returns True');
  Ambient := State;
end;

{$ASSERTIONS ON}
function DirOn: ShortString;
begin
  Fired := False;
  Assert(Bump, 'unreachable: Bump always returns True');
  DirOn := State;
end;

{$C-}
function DirOff: ShortString;
begin
  Fired := False;
  Assert(Bump, 'unreachable: Bump always returns True');
  DirOff := State;
end;
{$C+}

begin
  WriteLn('ambient=', Ambient);
  WriteLn('dir-on=', DirOn);
  WriteLn('dir-off=', DirOff);
  WriteLn('unit-ambient=', uassertambient.AssertState);
  WriteLn('unit-off=', uassertoff.AssertState);
end.
