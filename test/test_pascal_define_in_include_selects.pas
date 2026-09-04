program test_pascal_define_in_include_selects;
{ REGRESSION for bug-p-a-define-set-in-an-include-is-invisible-to-the-includers-
  own-include-selection, fixed 2026-09-04.

  ExpandIncludes saved and restored the define table at EVERY nesting level, so
  a define set inside an include was rolled back before the includer's own
  conditional was evaluated. The includer then took the ELSE arm on that pass
  and spliced the wrong file, while the LEXER -- walking the spliced text, where
  the define now sits inline -- took the THEN arm, whose body nobody had
  expanded. Neither arm's content reached the program and nothing errored,
  because each walk was self-consistent and they merely disagreed.

  Now only the OUTERMOST call restores, which is what still isolates one
  compilation unit from the next.

  BOTH arms exist and define DII_ARM differently, so a regression shows up as a
  wrong VALUE printed, not only as a missing identifier. }

{$I define_in_include_sets.inc}
{$IFDEF PXX_DEFINE_FROM_INCLUDE}
  {$I define_in_include_yes.inc}
{$ELSE}
  {$I define_in_include_no.inc}
{$ENDIF}

begin
  writeln(DII_ARM);
end.
