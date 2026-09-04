{ A claim taken inside an INCLUDE is a claim: the {$CLAIM} text is spliced into
  this unit and the lexer takes it here, durably, like any other.

  This header used to carry a second paragraph saying the claim was NOT visible
  to include SELECTION — an {$IFDEF} in this file choosing which further {$I} to
  follow during the expansion pass. That was true when written and frankS fixed
  it at 824e95953: ExpandIncludes restored its define table at every nesting
  level and now restores only at depth 0, so an include's own {$DEFINE} — and a
  {$CLAIM}, which that pass records as one — reaches its includer there too.
  Re-measured 2026-09-04: HEAD selects the arm the claim asks for; the pin,
  which has no {$CLAIM} at all, selects the other one.
  bug-p-a-define-set-in-an-include-is-invisible-to-the-includers-own-include-selection

  No row added here for that. The path is `PasDefine` in the expansion arm plus
  the depth-0 restore, which is exactly what frankS's define_in_include_selects
  already asserts — a {$CLAIM}-spelled copy would be a weaker instance of an
  assertion that exists, which is the same reason he declined a zero row from
  this fixture. What this file still asserts is the half his test does not: that
  the claim survives the expansion pass and is durable at LEXER time. }
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
