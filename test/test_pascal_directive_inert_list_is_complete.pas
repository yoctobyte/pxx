program test_pascal_directive_inert_list_is_complete;
{ EVERY name in PAS_INERT_DIRECTIVES, written out, asserting ZERO warnings.

  This is residual 2 of
  bug-p-a-spurious-unknown-directive-warning-cannot-fail-any-test-we-have:
  *nothing could see a name LEAVING the inert list.* The existing fixture,
  test_pascal_directive_unknown_warns.pas, asserts a TOTAL warning count, which
  catches a name ARRIVING -- but it mentions 26 of the 107 inert names, so a
  name that stops being inert warns in a file nobody compiles and every total
  stays put. Measured 2026-09-05: 81 of the 107 were unguarded.

  Same shape as the `library` case this repo keeps meeting: a feature's own
  tests assert the population they planted, so they cannot see what the feature
  took away.

  THIS FILE IS A SNAPSHOT AND MUST STAY HAND-MAINTAINED. Generating it from
  PAS_INERT_DIRECTIVES at test time would make it agree with the list by
  construction -- a guard that cannot fail, which is the exact defect the parent
  ticket is about. When you deliberately remove a name from the inert list,
  DELETE ITS LINE HERE IN THE SAME COMMIT; the diff is then the record of what
  stopped being inert, which is the thing nothing else keeps.

  Positive control, run 2026-09-05: removing `zerobasedstrings`, `y` and
  `apptype` from PAS_INERT_DIRECTIVES and rebuilding makes this file emit
  exactly three warnings, each naming its directive. So the rows are reached and
  the assertion can fail. A name whose bare spelling is swallowed by an earlier
  arm would NOT be caught here, and that control is what rules it out for these.

  The single letters are written with a + because several of them are also live
  switches in their sign form; the bare word form is used everywhere else.
  Neither form is arbitrary -- both were checked to reach the terminal arm. }

begin
  { single letters }
  {$d+}{$e+}{$f+}{$g+}{$i+}{$j+}{$l+}{$m+}{$n+}{$o+}{$p+}{$q+}{$s+}{$t+}
  {$u+}{$v+}{$w+}{$x+}{$y+}

  { the named directives }
  {$apptype}{$asmcpu}{$checkpointer}{$codealign}{$codepage}{$coperators}
  {$copyright}{$debuginfo}{$description}{$endregion}{$excessprecision}
  {$extendedsyntax}{$externalsym}{$fputype}{$goto}{$hints}{$hppemit}
  {$hugecode}{$hugepointerarithmeticnormalization}
  {$hugepointercomparisonnormalization}{$imagebase}{$implicitbuild}
  {$implicitexceptions}{$include}{$includepath}{$inline}{$legacyifend}
  {$libexport}{$librarypath}{$link}{$linkframework}{$linklib}
  {$localsymbols}{$macro}{$maxfpuregisters}{$maxstacksize}{$memory}
  {$minfpconstprec}{$minstacksize}{$mmx}{$modeswitch}{$namespace}
  {$nodefine}{$notes}{$objectchecks}{$objectpath}{$objexportall}
  {$openstrings}{$optimization}{$output_format}{$pascalmainname}{$pic}
  {$pointermath}{$pop}{$profile}{$push}{$pyextension}{$referenceinfo}
  {$region}{$resource}{$rtti}{$safefpuexceptions}{$saturation}
  {$screenname}{$setpeflags}{$setpeoptflags}{$setpeosversion}
  {$setpesubsysversion}{$setpeuserversion}{$smartlink}{$stackframes}
  {$static}{$stringchecks}{$syscalls}{$threading}{$threadname}
  {$typedaddress}{$typeinfo}{$unitpath}{$varpropsetter}{$varstringchecks}
  {$version}{$wait}{$warn}{$warnings}{$weakpackageunit}{$writeableconst}
  {$zerobasedstrings}
  WriteLn('ok');
end.
