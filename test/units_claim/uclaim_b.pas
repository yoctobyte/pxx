{ Second arrival, identical shape. It must find the name already claimed and
  compile itself out — this is the row that fails if {$CLAIM} does nothing. }
unit uclaim_b;
{$IFNDEF PXX_TEST_CAP}
  {$CLAIM PXX_TEST_CAP}
  {$DEFINE UCLAIM_B_WON}
{$ENDIF}
interface
procedure BWho;
implementation
procedure BWho;
begin
{$IFDEF UCLAIM_B_WON}
  writeln('b: claimed');
{$ELSE}
  writeln('b: stood down');
{$ENDIF}
end;
end.
