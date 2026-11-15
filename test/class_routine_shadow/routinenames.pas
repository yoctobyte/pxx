unit routinenames;
{ Routines whose names a program then uses for its own classes. }
interface
procedure TB(var p: Int64; b: Int64);
function Worker: Integer;
implementation
procedure TB(var p: Int64; b: Int64); begin p := p + b; end;
function Worker: Integer; begin Worker := 42; end;
end.
