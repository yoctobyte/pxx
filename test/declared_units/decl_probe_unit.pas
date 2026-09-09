unit decl_probe_unit;
{ THE UNIT THE CONDITIONAL HAS TO SEE.

  Two things live here and they test opposite directions. TProbeSeenType is what
  `$if declared(...)` in the program must find -- it is declared HERE, not in
  the program, so a scan of the program's own token stream cannot answer it.

  DECL_PROBE_LEAKED is the CONTROL, and it is why this unit has a `$define` it
  never uses. Answering `declared` means LEXING this unit, and lexing runs its
  directives; without a save/restore around the probe this define escapes into
  the program's own `$ifdef`, which is
  bug-p-a-units-define-leaks-into-the-units-it-uses reintroduced. fpc scopes it
  to this unit and so must we. }
{$mode delphi}
{$DEFINE DECL_PROBE_LEAKED}
interface
type
  TProbeSeenType = class
    v: Integer;
  end;
  { ONE NAME, TWO ARITIES, AND NO ARITY 0. A name can be declared at several
    arities in one unit, so a scan that stopped at the first name match would
    answer about whichever came first and be right by accident half the time.
    Deliberately no plain `TGenDelphi` -- that is what makes the bare row False. }
  TGenDelphi<T> = class
  end;
  TGenDelphi<T, S, R> = class
  end;
function ProbeUnitFn: Integer;
implementation
function ProbeUnitFn: Integer; begin ProbeUnitFn := 7; end;
end.
