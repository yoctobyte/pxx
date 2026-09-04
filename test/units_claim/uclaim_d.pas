{ …and it crosses the unit boundary exactly like an inline one. }
unit uclaim_d;
interface
procedure IncLater;
implementation
procedure IncLater;
begin
{$IFDEF PXX_TEST_INCCAP}
  writeln('later: include claim crossed the boundary');
{$ELSE}
  writeln('later: INCLUDE CLAIM DID NOT CROSS');
{$ENDIF}
end;
end.
