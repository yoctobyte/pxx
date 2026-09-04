{ A claim taken inside an INCLUDE is a claim: the {$CLAIM} text is spliced into
  this unit and the lexer takes it here, durably, like any other.

  What it is NOT is visible to include SELECTION — an {$IFDEF} in this file
  deciding which further {$I} to follow during the expansion pass. That pass
  snapshots and rolls back its define state per nesting level, so an include's
  own {$DEFINE} does not reach its includer THERE either; measured under the
  pinned compiler, so it predates {$CLAIM} and is not something this directive
  introduced. See bug-p-a-define-set-in-an-include-is-invisible-to-the-includers-own-include-selection. }
unit uclaim_c;
{$I uclaim_inc_sets.inc}
interface
procedure IncWho;
implementation
procedure IncWho;
begin
{$IFDEF PXX_TEST_INCCAP}
  writeln('inc: claim taken in an include');
{$ELSE}
  writeln('inc: INCLUDE CLAIM LOST');
{$ENDIF}
end;
end.
