program test_field_chain;

{ Regression: a property/field reached through a class-typed FIELD base
  (host.member.prop) must dereference the member's pointer before applying the
  property's field offset. Previously the offset was added to the address of the
  member slot, reading garbage. Exercises a 4-deep hierarchy + a host field. }

type
  TCtl = class
  private
    FH: Integer;
  public
    procedure Make;
    property H: Integer read FH write FH;
  end;
  TWin = class(TCtl) end;
  TFrm = class(TWin) end;
  TFrm1 = class(TFrm) end;
  THost = class
  public
    Main: TFrm;
  end;

procedure TCtl.Make;
begin
  FH := 9;
end;

var f: TFrm1; host: THost; base: TFrm;
begin
  f := TFrm1.Create;
  f.Make;
  host := THost.Create;
  host.Main := f;
  base := f;
  writeln('deep=', f.H);            { TFrm1 var }
  writeln('basevar=', base.H);      { base-typed local }
  writeln('field=', host.Main.H);   { base-typed field — the bug }
end.
