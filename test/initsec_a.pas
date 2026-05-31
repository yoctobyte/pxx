unit initsec_a;
interface
var Log: string;
procedure Note(const s: string);
implementation
procedure Note(const s: string);
begin
  Log := Log + s;
end;
initialization
  Log := 'A';
finalization
  Log := Log + 'fin';
end.
