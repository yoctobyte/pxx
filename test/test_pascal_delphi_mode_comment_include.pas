program test_pascal_delphi_mode_comment_include;
{$MODE DELPHI}
{ COMMENT NESTING IS MODE-DEPENDENT AND THE INCLUDE PRE-PASS HAS TO KNOW IT.

  In Delphi mode a brace comment does NOT nest, so the comment on the line
  below ends at its own close-brace -- the inner open-brace is ordinary text --
  and the dollar-include after it is LIVE. fpc 3.2.2 compiles this file and
  prints the string; under fpc mode the same two lines would instead read the
  include as comment text, which is why this fixture is mode-pinned.

  This is the exact case a first cut of the 2026-09-04 nested-comment fix
  BROKE: elfwriter.inc's brace scanner started honouring NestedComments, which
  PasInitDefines leaves True, while this file had asked for Delphi -- so the
  pre-pass swallowed the include as comment text and the program failed with
  `undefined variable (DMC)` on a file fpc accepts. The pre-pass now tracks the
  mode directive itself. Caught only by probing the opposite mode; nothing in
  the tree had this shape. }

{ outer { inner }
{$I delphi_mode_comment_real.inc}

begin
  writeln(DMC);
end.
