program TestInterfacesInherit;
{$interfaces corba}  {non-refcounted CORBA interfaces on plain classes; FPC needs this too}
{ Interface inheritance: `IBar = interface(IFoo)` extends IFoo. A class that
  implements IBar also implements IFoo; IBar dispatches IFoo's inherited methods
  through the leading IMT slots; an IBar value widens to IFoo. }
{$mode objfpc}
type
  IFoo = interface
    function F: Integer;
  end;
  IBar = interface(IFoo)
    function B: Integer;
  end;
  TA = class(IBar)
    function F: Integer;
    function B: Integer;
  end;

function TA.F: Integer; begin Result := 7; end;
function TA.B: Integer; begin Result := 9; end;

procedure WantFoo(f: IFoo); begin writeln('wf=', f.F); end;

var a: TA; bar: IBar; foo: IFoo;
begin
  a := TA.Create;
  bar := a;
  writeln('bar.B=', bar.B);     { 9 — own method }
  writeln('bar.F=', bar.F);     { 7 — inherited from IFoo }

  foo := a;                     { class implements derived -> also base }
  writeln('foo.F=', foo.F);     { 7 }

  foo := bar;                   { interface widening IBar -> IFoo }
  writeln('widen=', foo.F);     { 7 }

  WantFoo(bar);                 { pass derived interface where base expected }

  if a is IFoo then writeln('a is IFoo') else writeln('a not IFoo');
  if a is IBar then writeln('a is IBar') else writeln('a not IBar');
  if Supports(a, IFoo) then writeln('sup IFoo') else writeln('sup no');
end.
