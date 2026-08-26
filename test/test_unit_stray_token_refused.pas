{ A token that starts no declaration in a UNIT section is an ERROR.

  It used to be skipped, silently, and the parser carried on. A PROGRAM's
  declaration section rejected the identical token, so two paths through one
  concept disagreed and the unit one lost.

  The damage is not the missing message. A MISTYPED SECTION HEADER --
  `cosnt K = 5;` -- had the whole declaration thrown away, and the only complaint
  was `undefined variable (K)` at the USE site, in another file. Had nothing used
  K, the unit compiled clean with a declaration missing, which voids every "it
  compiled" signal that unit-shaped corpus code rests on.

  This is a NEGATIVE test: the compile must FAIL. See the Makefile entry.
  bug-p-stray-tokens-in-a-unit-declaration-section-are-silently-skipped }
program test_unit_stray_token_refused;
uses ustray;
begin
  WriteLn(F);
end.
