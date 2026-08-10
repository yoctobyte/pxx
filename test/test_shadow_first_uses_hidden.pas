{ The mirror of test_shadow_last_uses_wins: swapping the clause order swaps the
  answer. Both spellings are needed — a rule that always picked one unit would
  pass either test alone.
  bug-p-uses-order-does-not-decide-which-unit-wins }
program test_shadow_first_uses_hidden;
uses shadow_b, shadow_a;
begin
  writeln(Who);        { A }
  writeln(WhoP(1));    { A }
end.
