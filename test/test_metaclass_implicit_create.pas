program test_metaclass_implicit_create;
{$mode objfpc}{$H+}
uses SysUtils;

type
  { No constructor anywhere in this hierarchy: `Create` is the implicit
    TObject.Create, which the static TFoo.Create spelling always accepted and
    the metaclass spellings did not. }
  TA = class
    function Who: AnsiString; virtual;
  end;
  TAClass = class of TA;
  TB = class(TA)
    function Who: AnsiString; override;
  end;
  TC = class(TB)
    function Who: AnsiString; override;
  end;
  { A hierarchy that DOES declare a virtual ctor -- the arm that already
    worked, kept here so a regression in either direction shows up. }
  TP = class
    n: Integer;
    constructor Create(v: Integer); virtual;
    function Who: AnsiString; virtual;
  end;
  TPClass = class of TP;
  TQ = class(TP)
    constructor Create(v: Integer); override;
    function Who: AnsiString; override;
  end;

var cr: TAClass; pc: TPClass; a: TA; p: TP; i: Integer;

function TA.Who: AnsiString; begin Result := 'A'; end;
function TB.Who: AnsiString; begin Result := 'B'; end;
function TC.Who: AnsiString; begin Result := 'C'; end;
constructor TP.Create(v: Integer); begin inherited Create; n := v; end;
function TP.Who: AnsiString; begin Result := 'P' + IntToStr(n); end;
constructor TQ.Create(v: Integer); begin inherited Create(v * 10); end;
function TQ.Who: AnsiString; begin Result := 'Q' + IntToStr(n); end;

begin
  { implicit root ctor, empty parens }
  cr := TB; a := cr.Create(); WriteLn(a.Who); a.Free;
  { implicit root ctor, no parens, two levels down }
  cr := TC; a := cr.Create; WriteLn(a.Who); a.Free;
  { the base class itself }
  cr := TA; a := cr.Create; WriteLn(a.Who); a.Free;
  { the INLINE metaclass-cast receiver -- BuildMetaclassNew's other caller }
  cr := TB; a := TAClass(cr).Create; WriteLn('cast:' + a.Who); a.Free;
  { declared virtual ctor with an argument: dynamic dispatch, unchanged }
  pc := TQ; p := pc.Create(3); WriteLn(p.Who); p.Free;
  pc := TP; p := pc.Create(3); WriteLn(p.Who); p.Free;
  { the factory shape this exists for }
  for i := 0 to 1 do
  begin
    if i = 0 then cr := TB else cr := TC;
    a := cr.Create;
    WriteLn('loop', i, ':', a.Who, ':', a.ClassName);
    a.Free;
  end;
end.
