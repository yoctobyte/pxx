program test_virtual_proc;
{ Virtual PROCEDURE call as a statement must dispatch to the override (the
  result is discarded; emitter must still treat it as a statement root). }
type
  TA = class
    procedure Say; virtual;
  end;
  TB = class(TA)
    procedure Say; override;
  end;
procedure TA.Say; begin writeln('A'); end;
procedure TB.Say; begin writeln('B'); end;
var a: TA; b: TB;
begin
  b := TB.Create;
  a := b;
  a.Say;
  b.Say;
end.
