program test_own_lang_first_alias;
{ Own-language-first, the aliased form: a Pascal call site binds PASCAL's
  routine even though an imported C file defines the same name (case-
  insensitively), and the C one stays reachable by its alias.

  "if a symbol is defined in multiple languages, the _native_ language wins"
  — user, 2026-08-10. The other half of the decided rule is that nothing
  becomes unreachable: it just has to be asked for by name.
  feature-a-own-language-first-symbol-resolution }
uses math, './olf_cmath.c' as cm;
begin
  WriteLn('Exp=', Exp(1.0):0:4);          { Pascal's, not 42 }
  WriteLn('Sqrt=', Sqrt(16.0):0:4);       { Pascal's, not 43 }
  WriteLn('qSqrt=', math.Sqrt(16.0):0:4); { the Pascal-side qualifier agrees }
  WriteLn('cmExp=', cm.exp(1.0):0:4);     { C's, by name }
  WriteLn('cmCube=', cm.cube(3));         { no Pascal twin: reachability control }
end.
