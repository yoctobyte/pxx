program test_a_c_beside_the_source_outranks_a_pas_in_a_search_root;
{ THE UNIT SEARCH CHAIN IS AN ORDER, AND THIS PINS THE ONE RUNG THAT IS A
  DELIBERATE INVERSION.

  `uses csrcwins` can be answered by test/csrcwins.c, which sits beside this
  program, or by test/csrcwins_units/csrcwins.pas, reached through -Fu. The C
  file wins. That is not an accident of chain order: the search-root C probe was
  MOVED behind the entire Pascal chain by
  bug-a-a-c-include-path-captures-a-pascal-uses-and-emits-a-dynamic-import, and
  the source-directory one was deliberately left alone, because a .c next to the
  program you are compiling is an explicit local choice rather than something a
  flag dragged in.

  WHY THIS FIXTURE HAS TWO NAMES. `pick 111` on its own is equally consistent
  with "the search root was never searched" -- a different defect with an
  identical readout. `csrcroot` lives ONLY in the search root, so `root 333`
  says the -Fu stage is on the chain and reachable. Only together do the two
  rows mean "the root was searched AND the .c still outranked it", which is the
  claim.

  Measured 2026-09-09 in both directions before wiring: with test/csrcwins.c
  moved aside, the same command answers 222 from the search root. So the row's
  failure value is a real number produced by a real unit, not a default, a zero
  or a pointer width -- and 111 / 222 / 333 are mutually distinguishable.

  It exists because the chain was extracted into ResolveUsesUnitSource
  (pasparser_proc.inc) so a caller which is not the parser could ask the same
  question, and an extraction that quietly reorders these stages would answer
  222 with nothing else in the tree noticing.
  bug-p-declared-cannot-see-a-used-units-declarations }
uses csrcwins, csrcroot;
begin
  WriteLn('pick ', CWinsPick);
  WriteLn('root ', RootOnly);
end.
