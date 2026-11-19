program test_p_include_info_macros_expand_to_strings;
{ fpc's compile-time info macros expand to STRING literals. pxx left them "for
  the lexer", which had no handler, so `const d = {$I %DATE%};` compiled as the
  Integer 0 with no diagnostic. Matches fpc 3.2.2 for x86-64 Linux. The last one
  names an unset environment variable: '' plus a warning, as fpc.
  bug-p-compile-time-info-macros-are-not-implemented-and-silently-yield-zero }
const
  f = {$I %FILE%};
  l = {$I %LINE%};
  v = {$I %FPCVERSION%};
  c = {$I %FPCTARGETCPU%};
  t = {$I %FPCTARGET%};
  o = {$I %FPCTARGETOS%};
  h = {$I %PXX_INFO_MACRO_TEST_SURELY_UNSET%};
begin
  WriteLn('[', f, '][', l, '][', v, '][', c, '][', t, '][', o, '][', h, '] ', Length(l), ' ', Length(f));
end.
