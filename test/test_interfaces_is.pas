program TestInterfacesIs;
{ `obj is IFoo` — true iff obj's class implements the interface (directly or
  inherited). This is a real implementation check (FPC's CORBA `is` does not do
  one, so the expected values here are the correct semantics, not an FPC diff). }
{$mode objfpc}
type
  IFoo = interface
    function F: Integer;
  end;
  IBar = interface
    function B: Integer;
  end;
  TA = class(IFoo)
    function F: Integer;
  end;
  TC = class(TA)        { inherits IFoo from TA }
  end;
  TZ = class            { implements nothing }
    x: Integer;
  end;

function TA.F: Integer; begin Result := 7; end;

var a: TA; c: TC; z: TZ; foo: IFoo; n: TA;
begin
  a := TA.Create;
  c := TC.Create;
  z := TZ.Create;
  n := nil;

  if a is IFoo then writeln('a IFoo') else writeln('a no');
  if a is IBar then writeln('a IBar') else writeln('a noBar');
  if c is IFoo then writeln('c IFoo') else writeln('c no');
  if z is IFoo then writeln('z IFoo') else writeln('z no');
  if n is IFoo then writeln('nil yes') else writeln('nil no');

  foo := a;
  writeln('call=', foo.F);
end.
