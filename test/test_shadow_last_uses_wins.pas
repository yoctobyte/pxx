{ `uses a, b` — the LAST unit in the clause wins, as FPC does. pxx took the
  FIRST, ignoring the clause order entirely.

  Both call shapes are here because they bind through DIFFERENT code: a call
  with arguments goes through MatchProcCall (whose MatchElig now removes hidden
  candidates), while a PARAMETERLESS reference binds straight off FindProc and
  so was untouched by that — fixing only the first left `Who` still answering
  'A' while `WhoP(1)` answered 'B'.
  bug-p-uses-order-does-not-decide-which-unit-wins }
program test_shadow_last_uses_wins;
uses shadow_a, shadow_b;
begin
  writeln(Who);        { B }
  writeln(WhoP(1));    { B }
end.
