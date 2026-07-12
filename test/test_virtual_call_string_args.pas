program test_virtual_call_string_args;
{ Virtual + indirect calls skipped the AN_CALL argument conversions: a frozen
  concat ('ping' + CRLF) to a virtual method's AnsiString param arrived as a
  raw slot address (garbage Length — blcksock SendString hang), and string
  literals to Pointer params missed the +8 skip. }
const CRLF = #$0d + #$0a;
type
  TSock = class
    procedure SendString(Data: AnsiString); virtual;
  end;
  TProcS = procedure(Data: AnsiString);
procedure TSock.SendString(Data: AnsiString);
begin
  writeln('v-len=', Length(Data), ' d1=', Ord(Data[1]));
end;
procedure PlainSend(Data: AnsiString);
begin
  writeln('i-len=', Length(Data), ' d1=', Ord(Data[1]));
end;
var s: TSock; p: TProcS;
begin
  s := TSock.Create;
  s.SendString('ping' + CRLF);
  s.SendString('x' + #$0d);
  p := @PlainSend;
  p('abc' + CRLF);
end.
