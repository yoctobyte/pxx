program TestInterfacesParam;
{$interfaces corba}  {non-refcounted CORBA interfaces on plain classes; FPC needs this too}
{ Interface values across procedure boundaries and identity:
  - implicit class->interface coercion at a call site and into a Result
  - identity =/<> compares the referenced instance, not the shared IMT
  - assigning and comparing nil }
{$mode objfpc}
type
  IFoo = interface
    function F: Integer;
  end;
  TA = class(IFoo)
    function F: Integer;
  end;

function TA.F: Integer; begin Result := 7; end;

procedure CallIt(f: IFoo);
begin
  writeln('viaparam=', f.F);
end;

function MakeFoo(a: TA): IFoo;
begin
  Result := a;            { class->interface coercion into the Result }
end;

var a, b: TA; f, g, h: IFoo;
begin
  a := TA.Create;
  b := TA.Create;
  CallIt(a);              { implicit coercion at the call site }
  f := MakeFoo(a);
  writeln('result=', f.F);

  g := a; h := b;
  if f = g then writeln('fg same') else writeln('fg diff');   { same instance }
  if f = h then writeln('fh same') else writeln('fh diff');   { different }
  if f <> h then writeln('fh ne') else writeln('fh eq');

  if f = nil then writeln('f nil') else writeln('f set');
  f := nil;
  if f = nil then writeln('now nil') else writeln('still set');
end.
