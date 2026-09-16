unit wmid;
interface
uses wbase;
function Which: Integer;
implementation
function Which: Integer;
begin
{$if sizeof(tcompilerwidechar) = 0}
  Which := 999;      { only reachable if an unresolved sizeof answers 0 }
{$else}
  Which := 1;
{$endif}
end;
end.
