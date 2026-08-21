program test_interface_guid_and_supports;
{$mode objfpc}{$H+}
uses SysUtils;

type
  IHello = interface
    ['{11111111-2222-3333-4444-555555555555}']
    function Hello: AnsiString;
  end;
  IBye = interface
    ['{99999999-8888-7777-6666-555544443333}']
    function Bye: AnsiString;
  end;
  TImpl = class(TInterfacedObject, IHello)
    function Hello: AnsiString;
  end;
  TPlain = class end;

var impl: TImpl; pl: TPlain; f: IHello; b: IBye; g, h: TGuid; ok: Boolean;

function TImpl.Hello: AnsiString; begin Result := 'hello'; end;

{ a const TGuid PARAMETER: the interface name must match it, which needs the
  node to carry TGuid's record id, not a bare pointer }
function ShowG(const x: TGuid): AnsiString;
var i: Integer;
begin
  Result := '';
  for i := 0 to 15 do Result := Result + IntToHex(PByte(@x)[i], 2);
end;

begin
  { an interface NAME used as a value is its GUID, in TGuid memory order }
  g := IHello; h := IBye;
  WriteLn(ShowG(g));
  WriteLn(ShowG(h));
  WriteLn('distinct=', BoolToStr(ShowG(g) <> ShowG(h), True));
  h := IHello;
  WriteLn('stable=', BoolToStr(ShowG(g) = ShowG(h), True));
  WriteLn('asarg=', ShowG(IHello));

  impl := TImpl.Create; impl._AddRef;
  pl := TPlain.Create;

  { the name passed straight to GetInterface }
  WriteLn('getintf=', BoolToStr(impl.GetInterface(IHello, f), True),
          ' ', BoolToStr(f <> nil, True));

  { Supports, three-argument form }
  ok := Supports(impl, IHello, f);
  WriteLn('hit=', BoolToStr(ok, True), ' call=', f.Hello);
  ok := Supports(impl, IBye, b);
  WriteLn('miss=', BoolToStr(ok, True), ' nil=', BoolToStr(b = nil, True));
  { f is SET here: a failed query must CLEAR it, or a stale interface survives }
  ok := Supports(pl, IHello, f);
  WriteLn('cleared=', BoolToStr(ok, True), ' ', BoolToStr(f = nil, True));
  WriteLn('nilinst=', BoolToStr(Supports(TObject(nil), IHello, f), True),
          ' ', BoolToStr(f = nil, True));

  { the two-argument form is untouched }
  WriteLn('two=', BoolToStr(Supports(impl, IHello), True),
          BoolToStr(Supports(pl, IHello), True));
  if Supports(impl, IHello, f) then WriteLn('iff=', f.Hello) else WriteLn('iff=no');

  f := nil;
  pl.Free;
end.
