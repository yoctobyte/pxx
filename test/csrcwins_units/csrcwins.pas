unit csrcwins;
{ The LOSING candidate, and it has to be a real compilable unit -- a row that
  passes because this file is broken would prove nothing about ordering. }
interface
function CWinsPick: Integer;
implementation
function CWinsPick: Integer; begin CWinsPick := 222; end;
end.
