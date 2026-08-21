{ Site class 3 of feature-a-emitted-nil-checks: a method call on a NIL
  interface. Both flavours are here because they are declared differently and
  it is cheap to be sure -- COM (refcounted, IUnknown-derived, the default) and
  CORBA (`{$interfaces corba}`, plain classes, no refcounting). They share one
  lowering path (AN_INTF_CALL; an interface VALUE is a single pointer, the
  instance), so this is a claim about that path, not two paths.

  Why the check sits on the INSTANCE pointer and not on the IMT: the IMT is
  resolved by PXXIntfIMTOf(self, ci), which walks the instance's RTTI blob. A
  nil interface therefore used to fault INSIDE a runtime helper -- a fault whose
  PC names PXXIntfIMTOf, several frames from the `i.Go` the programmer wrote.

  Procedure and function are both exercised: a function's result path differs
  enough in lowering that it can regress on its own.

  Expected: go / val=7 / caught proc / caught func / still running -- and the
  program CONTINUES, which is the entire point of the ticket. }
program test_nil_check_interface;
{$mode objfpc}
uses SysUtils;
type
  IThing = interface ['{a0000000-0000-0000-0000-000000000001}']
    procedure Go;
    function Val: longint;
  end;
  TThing = class(TInterfacedObject, IThing)
    procedure Go;
    function Val: longint;
  end;
procedure TThing.Go; begin writeln('go'); end;
function TThing.Val: longint; begin Val := 7; end;

{$interfaces corba}
type
  ICorba = interface
    function W: longint;
  end;
  TCorba = class(TObject, ICorba)
    function W: longint;
  end;
function TCorba.W: longint; begin W := 9; end;

var i: IThing; c: ICorba; t: TCorba;
begin
  i := TThing.Create;
  i.Go;
  writeln('val=', i.Val);
  i := nil;
  try
    i.Go;
  except
    on E: Exception do writeln('caught proc: ', E.Message);
  end;
  try
    writeln(i.Val);
  except
    on E: Exception do writeln('caught func: ', E.Message);
  end;
  t := TCorba.Create;
  c := t;
  writeln('corba=', c.W);
  c := nil;
  try
    writeln(c.W);
  except
    on E: Exception do writeln('caught corba: ', E.Message);
  end;
  writeln('still running');
end.
