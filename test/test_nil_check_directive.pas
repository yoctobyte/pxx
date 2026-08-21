{ Site class 4 of feature-a-emitted-nil-checks, and the {$NILCHECKS} directive
  that governs it.

  The directive is TRI-state (default / on / off), which no other check
  directive here is, because one directive governs two site classes whose
  DEFAULTS disagree:

    * a CALL on a nil receiver / procvar / interface is checked by default --
      it costs ~2% and the fault it replaces lands frames from the call site,
      or, on a target with no signal runtime, nowhere at all;
    * a bare `p^` is NOT checked by default -- that is a test in whatever loop
      the deref sits in, and on the PC targets the MMU already reports it at
      the right instruction.

  So a plain Boolean could not say "the author said nothing", which is exactly
  the state those two defaults disagree about. This test pins all four corners:

    DerefDefault  -- no directive, `p^` on nil: NOT checked (returns garbage or
                     faults; here we only prove it is not RAISING, by never
                     passing it nil -- the nil half is the --no-nil-check row
                     in test_fpc_mem_errors, which owns the raw-fault direction)
    DerefOn       -- {$nilchecks on}: `p^` read AND write both raise
    CallDefault   -- no directive, method on nil: raises (site class 2)
    CallOff       -- {$nilchecks off}: method on nil is NOT checked, so the
                     method runs on a nil instance exactly as it did before the
                     feature landed -- which is the escape hatch a hot loop needs

  Expected: 3 / 3 / caught read / caught write / go / done }
program test_nil_check_directive;
uses SysUtils;
type PInt = ^Integer;

function DerefDefault(q: PInt): Integer;
begin
  DerefDefault := q^;
end;

{$nilchecks on}
function DerefOn(q: PInt): Integer;
begin
  DerefOn := q^;
end;

procedure StoreOn(q: PInt);
begin
  q^ := 5;
end;
{$nilchecks off}

type
  TT = class
    procedure Go;
  end;
procedure TT.Go; begin writeln('go'); end;

{ Declared in the {$nilchecks off} region: the receiver check that site class 2
  emits by default must NOT be here. }
procedure CallOff(o: TT);
begin
  o.Go;
end;

var p: PInt; n: Integer; t: TT;
begin
  n := 3; p := @n;
  writeln(DerefDefault(p));
  writeln(DerefOn(p));
  p := nil;
  try
    writeln(DerefOn(p));
  except
    on E: Exception do writeln('caught read: ', E.Message);
  end;
  try
    StoreOn(p);
  except
    on E: Exception do writeln('caught write: ', E.Message);
  end;
  t := nil;
  CallOff(t);
  writeln('done');
end.
