program test_delphi_bare_proc_method_arg;
{$mode delphi}
{ bug-p-a-bare-routine-name-is-refused-as-a-method-argument.

  A Delphi bare routine name standing as a whole argument was tried only at the
  FREE-call argument loops, so `FreeRun(MyCompare)` compiled while
  `s.Run(MyCompare)` answered `undefined variable (MyCompare)` -- the name never
  became a value at all on the method path. Seven parameter-driven argument
  loops reach an argument expression and five funnel through ParseArgExpr, so
  the attempt moved THERE rather than being added to each; the free sites' own
  calls are now redundant and harmless.

  Rows 1-5 are the five spellings, measured against fpc 3.2.2 -Mdelphi, which
  accepts all five. Before the fix only BARE_METHOD failed, so it is the row
  that carries the bug and the other four are the controls that say the fix did
  not simply loosen everything.

  Rows 6-7 are the OPPOSITE risk and are the reason this test is not just the
  five: TryDelphiBareProcArg deliberately does NOT take the address of a
  paramless function or an all-defaulted one, because those parse as a
  value-producing call (call-first precedence) and only reach @F through
  MatchCallDelphiProcAddr's retry when the sink really is procedural. Moving
  the attempt into ParseArgExpr makes that guard run at five more sites, so if
  it were wrong these two rows would print a POINTER instead of a value --
  which is what bug-p-bare-all-defaulted-routine-refused-in-argument-position
  measured (4247470 against FPC's 6). }

type
  TCmp = function(a, b: Integer): Integer;
  TSorter = class
    procedure Run(c: TCmp);
    procedure Want(v: Integer);
  end;

var
  fails: Integer;
  s: TSorter;
  v: TCmp;
  LastWanted: Integer;   { declared HERE: the Want method reads it, and pxx
                           requires a global to precede its use. }

procedure Chk(got, want: Integer; const what: AnsiString);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

function MyCompare(a, b: Integer): Integer;
begin Result := a - b; end;

function Paramless: Integer;
begin Result := 11; end;

function AllDefaulted(k: Integer = 6): Integer;
begin Result := k; end;

procedure TSorter.Run(c: TCmp);
begin Chk(c(5, 3), 2, 'INVOKED'); end;

procedure TSorter.Want(v: Integer);
begin Chk(v, LastWanted, 'WANT'); end;

procedure FreeRun(c: TCmp);
begin Chk(c(5, 3), 2, 'INVOKED_FREE'); end;

begin
  fails := 0;
  s := TSorter.Create;

  { 1..5 -- the five spellings. Only BARE_METHOD was broken. }
  v := MyCompare;        Chk(v(5, 3), 2, 'ASSIGN');
  FreeRun(MyCompare);                              { BARE_FREE      }
  FreeRun(@MyCompare);                             { AT_FREE        }
  s.Run(@MyCompare);                               { AT_METHOD      }
  s.Run(MyCompare);                                { BARE_METHOD <- }

  { 6..7 -- a paramless / all-defaulted function must still be CALLED in
    argument position, at a METHOD site, not have its address taken. }
  LastWanted := 11; s.Want(Paramless);
  LastWanted := 6;  s.Want(AllDefaulted);

  if fails = 0 then WriteLn('BAREPROCARG OK')
  else WriteLn('BAREPROCARG FAILED ', fails);
end.
