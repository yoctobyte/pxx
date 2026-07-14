{ The advanced-record legality checks must reject the invalid shapes WITHOUT breaking the
  valid ones. A NAMED, top-level record may have private/public sections, consts, methods,
  properties, a static class method, and a constructor WITH a mandatory parameter — the RTL
  leans on all of it (TPoint/TRect are advanced records).

  Guards the false-positive side of the b347 record rules. }
program test_record_rules_ok;
{$mode objfpc}{$modeswitch advancedrecords}
type
  TPt = record
  private
    FTag: Integer;
  public
    const Origin = 0;
    var X, Y: Integer;
    constructor Create(ax, ay: Integer);      { has a mandatory parameter }
    function Sum: Integer;
    class function Zero: TPt; static;         { class method IS static }
    property Tag: Integer read FTag write FTag;
  end;

constructor TPt.Create(ax, ay: Integer);
begin
  X := ax; Y := ay; FTag := 0;
end;

function TPt.Sum: Integer;
begin
  Sum := X + Y;
end;

class function TPt.Zero: TPt; static;
begin
  Zero.X := 0; Zero.Y := 0;
end;

var
  p: TPt;
  z: TPt;
  fails: Integer;

procedure Check(const what: AnsiString; got, want: Integer);
begin
  if got = want then writeln('ok   ', what, ' = ', got)
  else begin writeln('FAIL ', what, ' = ', got, ' (want ', want, ')'); fails := fails + 1; end;
end;

{ a record type declared inside a routine, and an anonymous one, are still fine
  with plain FIELDS — only advanced members are refused }
procedure LocalPlainRecordStillWorks;
type
  TLocal = record a, b: Integer; end;
var
  L: TLocal;
  anon: record m, n: Integer; end;
begin
  L.a := 3; L.b := 4;
  anon.m := 5; anon.n := 6;
  Check('local record fields', L.a + L.b, 7);
  Check('anonymous record fields', anon.m + anon.n, 11);
end;

begin
  fails := 0;
  p := TPt.Create(2, 3);
  Check('record ctor with a parameter', p.Sum, 5);
  p.Tag := 9;
  Check('record property', p.Tag, 9);
  Check('record const', TPt.Origin, 0);
  z := TPt.Zero;
  Check('static class function', z.X + z.Y, 0);
  LocalPlainRecordStillWorks;
  if fails = 0 then writeln('PASS') else writeln('FAILED ', fails);
end.
