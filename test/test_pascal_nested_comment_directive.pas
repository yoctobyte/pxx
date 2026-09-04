program test_pascal_nested_comment_directive;
{ REGRESSION, fixed 2026-09-04 in elfwriter.inc's ExpandIncludes.

  That pass counted brace-comment nesting on an inner dollar-directive only,
  never on a plain open-brace. So in a comment nested TWO deep the inner plain
  open-brace was not counted, its close-brace decremented a level it never
  opened, and the pass left the comment early -- reading everything after it as
  LIVE directives, while the lexer, which does count it under NestedComments,
  still saw comment text. The two walks disagreed about where a comment ends.

  The line below is the failing shape. nested_comment_absent.inc DOES NOT
  EXIST, deliberately: if the pre-pass ever leaves the comment early again it
  tries to open that file and this test fails to COMPILE, loudly. fpc 3.2.2
  compiles this file. Keep prose in this file free of unpaired braces -- a lone
  one in a sentence opens a level under NestedComments, in pxx and in fpc
  alike. }

{ outer { inner {$DEFINE NC_LEAKED} } still comment: {$I nested_comment_absent.inc} }

{$I nested_comment_live.inc}

var
  score: Integer;
begin
  score := 0;
  { The define above sits inside a comment and must not reach either walk's
    define table. This is the runtime half; the compile half is the absent
    include named there. }
{$IFDEF NC_LEAKED}
  score := score + 100;
{$ELSE}
  score := score + 1;
{$ENDIF}
  if NC_LIVE = 'live' then score := score + 1;
  writeln(score);
end.
