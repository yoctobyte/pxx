{ Set-once, never cleared: a claim you can release is not a claim. {$UNDEF}
  reaches the define table and the claim list is not in it. }
unit uclaim_undef;
{$UNDEF PXX_TEST_CAP}
interface
procedure UndefWho;
implementation
procedure UndefWho;
begin
{$IFDEF PXX_TEST_CAP}
  writeln('undef: claim survived');
{$ELSE}
  writeln('undef: UNDEF CLEARED THE CLAIM');
{$ENDIF}
end;
end.
