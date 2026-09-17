{ The four shapes an old-style `object` may NOT have. This is the positive
  control for test_object_value_ctor.pas: that file proves a VMT-less object's
  constructor WORKS, and this one proves the acceptance did not widen to the
  VMT-bearing shapes, which pxx cannot represent.

  Every row here is something fpc compiles and runs. Each is refused because pxx
  lowers `object` as a value type with no VMT, and each message says so and names
  a ticket -- refusing loudly rather than accepting quietly is the whole point.

  ONE SOURCE, FOUR COMPILES, SELECTED BY -d. Not four rows in one file, and not
  four files: every one of these diagnostics HALTS, so a single compile can only
  ever report the first of them and the other three rows would be certified by a
  compiler that had stopped before reaching them. Each row must therefore be the
  only row in its run, and the Makefile drives four runs asserting four distinct
  messages and `test ! -e` on each.
  feature-p-legacy-value-object-types }
program test_object_value_ctor_fail;

type
  TBase = object
    X: Integer;
    constructor Init;
{$IFDEF ROW_VIRTUAL}
    procedure Show; virtual;          { row 1: a virtual method needs a VMT }
{$ENDIF}
  end;

{$IFDEF ROW_ANCESTOR}
  TDerived = object(TBase)            { row 2: an ancestor needs a VMT }
    Y: Integer;
  end;
{$ENDIF}

  PBase = ^TBase;

constructor TBase.Init;
begin X := 1; end;

{$IFDEF ROW_VIRTUAL}
procedure TBase.Show;
begin WriteLn(X); end;
{$ENDIF}

var
  p: PBase;
begin
{$IFDEF ROW_NEW}
  New(p, Init);                       { row 3: extended New dispatches via VMT }
{$ELSE}
  New(p);
{$ENDIF}
  p^.Init;
{$IFDEF ROW_DISPOSE}
  Dispose(p, Done);                   { row 4: extended Dispose, likewise }
{$ELSE}
  Dispose(p);
{$ENDIF}
end.
