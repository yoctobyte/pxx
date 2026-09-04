{ First arrival: takes the claim and crafts its code. The plain {$DEFINE} beside
  it is the control — that one must stay inside this unit, exactly as it does
  under FPC, or {$CLAIM} has quietly made every define global. }
unit uclaim_a;
{$DEFINE UCLAIM_A_PLAIN}
{$IFNDEF PXX_TEST_CAP}
  {$CLAIM PXX_TEST_CAP}
  {$DEFINE UCLAIM_A_WON}
{$ENDIF}
interface
procedure AWho;
implementation
procedure AWho;
begin
{$IFDEF UCLAIM_A_WON}
  writeln('a: claimed');
{$ELSE}
  writeln('a: stood down');
{$ENDIF}
end;
end.
