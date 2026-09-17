program test_p_a_conditional_directive_refusal_names_the_directive_s_line;
{ THE CONTROL THAT MUST NOT COMPILE, and what it pins is the LINE, not the
  refusal. The refusal itself is correct and is asserted elsewhere; this row
  exists because it pointed at the wrong place.

  `Error` prints the CURRENT TOKEN's line, and the conditional-expression
  evaluator runs from the directive handler, when the token stream is wherever
  the last tokenised line left it. Measured 2026-09-17 against FPC's own
  compiler: nld, nadd and hlcgobj reported conditional-directive refusals at
  lines 1334, 1112 and 1821 while the directives are at 700, 1352 and 4156 --
  two pointing BACKWARDS, one FORWARDS, all three at ordinary statements that
  explain nothing. A reader who trusts the number opens the wrong code, which
  is the cost: a wrong line does not error, it points somewhere.

  THREE WRONG ANSWERS ARE EXCLUDED BY CONSTRUCTION, and that is why the fixture
  is shaped this way rather than being three lines long:
    - the failing directive is NOT the first line, so `1` fails;
    - a directive that EVALUATES FINE sits above it, so reporting the first
      directive in the file fails;
    - a body follows below, so reporting the lexer's position fails -- that is
      the answer the real defect gave.
  The Makefile row asserts the exact line, read out of this file rather than
  copied, so the number cannot rot. }
{$define ALREADY_HERE}
{$if defined(ALREADY_HERE)}
  { this arm is taken, and evaluating it moves nothing the row below depends on }
{$endif}
const
  NOPE_WRONG_LINE = 1;
{$if sizeof(nosuchtypeatall) = 8}
  { unreachable either way -- the directive above is the subject }
{$endif}
begin
  WriteLn('TOOK A BRANCH -- an unsizeable type was sized', NOPE_WRONG_LINE);
  WriteLn('filler so the lexer position is far below the directive');
  WriteLn('filler');
  WriteLn('filler');
end.
