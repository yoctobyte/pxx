program test_p_a_deferred_conditional_refusal_names_the_directive_s_line;
{ THE SECOND DOOR, and it is the reason this is a separate file rather than
  another row in the one beside it.

  A refusal from the `in` arm is not RAISED where it is found: the operand is
  poisoned (kind 2) with a reason, the poison propagates to the top of the
  expression, and one site turns it into a diagnostic -- `Error(PasCondValWhy[0])`.
  Fixing the evaluator by rewriting every `Error('conditional directive...')`
  call misses that site COMPLETELY, because its argument is a variable and the
  literal prefix is nowhere on the line. Measured 2026-09-17: after that sweep,
  nadd and hlcgobj reported their directive's line and nld still reported 1334
  for a directive on line 700 -- two doors, one grep, and the grep found the
  door that was easy to see.

  That is CLAUDE.md's "the sibling is usually a SPELLING, not a shape": both
  spellings mean the same thing to whoever wrote the source, so neither the
  construct name nor the message distinguishes them. This row makes the
  deferred door fail on its own, so a future sweep of the direct one cannot
  certify it.

  Same three exclusions as the file beside it: not line 1, a directive that
  evaluates fine above, a body below. }
{$define ALREADY_HERE}
{$if defined(ALREADY_HERE)}
  { taken, and it must not become the reported line }
{$endif}
const
  NOPE_NOT_A_SET = 7;
{$if (3 in NOPE_NOT_A_SET)}
  { unreachable either way }
{$endif}
begin
  WriteLn('TOOK A BRANCH -- a non-set was read as a set', NOPE_NOT_A_SET);
  WriteLn('filler so the lexer position is far below the directive');
  WriteLn('filler');
end.
