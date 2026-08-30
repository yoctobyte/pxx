{ A C header supplied by a `-Fu`/`-I` search root SHADOWS the compiler-anchored
  one of the same name.

  `uses math_ext` normally resolves lib/rtl/math_ext.h, which declares both abs
  and labs. test/uses_shadow/math_ext.h declares only abs, so this program --
  which calls labs -- is the discriminator: it must COMPILE with no search root
  and FAIL with -Futest/uses_shadow. Both rows are asserted in the Makefile;
  the failing one is the one that carries the information.

  Pinned because the ordering has no other witness in the suite, and because a
  fix to
  bug-a-a-c-include-path-captures-a-pascal-uses-and-emits-a-dynamic-import
  broke it once already, silently. }
program test_uses_shadow_root_beats_the_rtl_header;
uses math_ext;
begin
  writeln(labs(-5));
end.
