program TestInterfacesAs;
{$interfaces corba}  {non-refcounted CORBA interfaces on plain classes; FPC needs this too}
{ `obj as IFoo` — checked cast to an interface VALUE. Yields a CORBA fat pointer
  the same as a class-to-interface assignment, but with a runtime implementation
  check: nil passes through as a null fat pointer; a non-implementer traps. }
{$mode objfpc}
type
  IFoo = interface
    function F: Integer;
  end;
  TA = class(IFoo)
    function F: Integer;
  end;
  TC = class(TA)        { inherits IFoo from TA }
  end;

function TA.F: Integer; begin Result := 7; end;

var a: TA; c: TC; base: TA; foo: IFoo;
begin
  a := TA.Create;
  c := TC.Create;

  { assign the cast to an interface var, then dispatch }
  foo := a as IFoo;
  writeln('a.F=', foo.F);          { 7 }

  { dynamic IMT: a base-typed source still picks the derived class's IMT }
  base := c;
  foo := base as IFoo;
  writeln('c.F=', foo.F);          { 7 — TC inherits TA.F }

  { direct dispatch through the cast expression }
  writeln('direct=', (a as IFoo).F);   { 7 }

  { nil passes through }
  base := nil;
  foo := base as IFoo;
  writeln('done');
end.
