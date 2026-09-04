{ Compiled BEFORE the claimer. `{$CLAIM}` is NOT retroactive, so this unit must
  report that it saw nothing — the ordering half of
  feature-p-defineglobal-a-define-that-crosses-unit-boundaries. }
unit uclaim_early;
interface
procedure EarlyWho;
implementation
procedure EarlyWho;
begin
{$IFDEF PXX_TEST_CAP}
  writeln('early: sees the claim');
{$ELSE}
  writeln('early: no claim yet');
{$ENDIF}
end;
end.
